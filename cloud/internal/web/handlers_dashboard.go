package web

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"sort"
	"strings"

	"github.com/Makhkets/commy/cloud/internal/manifest"
	"github.com/Makhkets/commy/cloud/internal/store"
)

type projectsData struct {
	Projects []store.Project
	Form     struct{ ID, Name, Key string }
}

func (s *Server) projects(w http.ResponseWriter, r *http.Request) {
	si := current(r)
	s.render(w, r, http.StatusOK, "projects", view{
		Title: tr(langOf(r), "projects.title"), User: si.user, CSRF: si.session.CSRF,
		Data: projectsData{Projects: s.store.Projects(si.user.ID)},
	})
}

func (s *Server) createProject(w http.ResponseWriter, r *http.Request) {
	si := current(r)
	lang := langOf(r)
	data := projectsData{Projects: s.store.Projects(si.user.ID)}
	data.Form.ID = strings.TrimSpace(r.PostFormValue("id"))
	data.Form.Name = strings.TrimSpace(r.PostFormValue("name"))
	data.Form.Key = strings.TrimSpace(r.PostFormValue("key"))
	again := func(status int, key string) {
		s.render(w, r, status, "projects", view{Title: tr(lang, "projects.title"), User: si.user, CSRF: si.session.CSRF, Error: tr(lang, key), Data: data})
	}
	if !manifest.ValidID(data.Form.ID) {
		again(http.StatusBadRequest, "projects.badID")
		return
	}
	if !validKey(data.Form.Key) {
		again(http.StatusBadRequest, "projects.badKey")
		return
	}
	if !si.user.Admin && len(data.Projects) >= s.cfg.MaxProjects {
		again(http.StatusForbidden, "projects.limit")
		return
	}
	name := data.Form.Name
	if name == "" || len([]rune(name)) > manifest.MaxName {
		name = data.Form.ID
	}
	_, err := s.store.AddProject(store.Project{ID: data.Form.ID, OwnerID: si.user.ID, Name: name, Key: data.Form.Key}, si.user.Email)
	if errors.Is(err, store.ErrExists) {
		again(http.StatusConflict, "projects.taken")
		return
	}
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/cloud/p/"+data.Form.ID, http.StatusSeeOther)
}

// owned finds a project the signed-in user may act on: their own, or any
// for the admin.
func (s *Server) owned(w http.ResponseWriter, r *http.Request) (*store.Project, bool) {
	p, err := s.store.Project(r.PathValue("id"))
	if err != nil {
		s.fail(w, r, http.StatusNotFound, "error.notFound")
		return nil, false
	}
	si := current(r)
	if p.OwnerID != si.user.ID && !si.user.Admin {
		s.fail(w, r, http.StatusNotFound, "error.notFound")
		return nil, false
	}
	return p, true
}

type projectData struct {
	Project    *store.Project
	Latest     *store.Release
	Releases   []store.Release
	Events     []store.Event
	Health     []store.Health
	Stats      []store.DayStat
	MaxVisits  int
	Total      int
	Tokens     []store.Token
	NewToken   string
	Rendezvous string
	Points     []string
	Header     string
	NextSeq    int64
	Form       publishForm
	Apps       []string
}

type publishForm struct {
	Origin, Mirrors, Rendezvous, Name, NextKey string
}

func (s *Server) projectView(r *http.Request, p *store.Project) projectData {
	d := projectData{
		Project:    p,
		Releases:   s.store.Releases(p.ID),
		Events:     s.store.Events(p.ID),
		Stats:      s.store.Stats(p.ID, 30),
		Tokens:     s.store.Tokens(p.ID),
		Rendezvous: s.cfg.BaseURL + "/r/" + p.ID,
		NextSeq:    1,
		Apps:       pageApps,
	}
	if len(d.Events) > 30 {
		d.Events = d.Events[:30]
	}
	if latest, err := s.store.Latest(p.ID); err == nil {
		d.Latest = latest
		d.Header = latest.Compact
		d.NextSeq = latest.Seq + 1
		if parsed, err := manifest.Parse(latest.Compact); err == nil {
			m := parsed.Manifest
			d.Form = publishForm{Origin: m.Origin, Mirrors: strings.Join(m.Mirrors, "\n"), Rendezvous: strings.Join(m.Rendezvous, "\n"), Name: m.Name}
			d.Points = m.Rendezvous
		}
	} else {
		d.Form = publishForm{Rendezvous: d.Rendezvous, Name: p.Name}
	}
	for _, day := range d.Stats {
		d.Total += day.Unique
		if day.Unique > d.MaxVisits {
			d.MaxVisits = day.Unique
		}
	}
	health := s.store.HealthOf(p.ID)
	for _, h := range health {
		d.Health = append(d.Health, h)
	}
	sort.Slice(d.Health, func(i, j int) bool { return d.Health[i].URL < d.Health[j].URL })
	return d
}

func (s *Server) project(w http.ResponseWriter, r *http.Request) {
	p, ok := s.owned(w, r)
	if !ok {
		return
	}
	si := current(r)
	flash := ""
	if r.URL.Query().Get("saved") != "" {
		flash = tr(langOf(r), "p.saved")
	}
	if seq := r.URL.Query().Get("published"); seq != "" {
		flash = fmt.Sprintf(tr(langOf(r), "p.published"), atoi(seq))
	}
	s.render(w, r, http.StatusOK, "project", view{Title: p.Name, User: si.user, CSRF: si.session.CSRF, Flash: flash, Data: s.projectView(r, p)})
}

// publish checks a signed manifest against the project and stores it. The
// error is a dictionary key, or a formatted p.badManifest.
func (s *Server) publish(p *store.Project, compact, by, lang string) (*manifest.Signed, string) {
	signed, err := manifest.Parse(compact)
	if err != nil {
		return nil, fmt.Sprintf(tr(lang, "p.badManifest"), err.Error())
	}
	if signed.Manifest.ID != p.ID {
		return nil, tr(lang, "p.wrongID")
	}
	m := signed.Manifest
	if m.Key != p.Key && (p.NextKey == "" || m.Key != p.NextKey) {
		return nil, tr(lang, "p.wrongKey")
	}
	if err := signed.Verify(); err != nil {
		return nil, tr(lang, "p.wrongKey")
	}
	err = s.store.Publish(p.ID, store.Release{Seq: m.Seq, Compact: signed.Compact, Origin: m.Origin, Mirrors: m.Mirrors, By: by}, m.Key, m.NextKey)
	if errors.Is(err, store.ErrStale) {
		return nil, tr(lang, "p.stale")
	}
	if err != nil {
		return nil, "internal error"
	}
	return signed, ""
}

func (s *Server) publishFromDashboard(w http.ResponseWriter, r *http.Request) {
	p, ok := s.owned(w, r)
	if !ok {
		return
	}
	si := current(r)
	signed, problem := s.publish(p, r.PostFormValue("manifest"), si.user.Email, langOf(r))
	if problem != "" {
		d := s.projectView(r, p)
		s.render(w, r, http.StatusBadRequest, "project", view{Title: p.Name, User: si.user, CSRF: si.session.CSRF, Error: problem, Data: d})
		return
	}
	go s.checkProject(p.ID)
	http.Redirect(w, r, fmt.Sprintf("/cloud/p/%s?published=%d", p.ID, signed.Manifest.Seq), http.StatusSeeOther)
}

var accentPattern = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)

func (s *Server) savePage(w http.ResponseWriter, r *http.Request) {
	p, ok := s.owned(w, r)
	if !ok {
		return
	}
	si := current(r)
	page := store.Page{
		Title:   clip(r.PostFormValue("title"), 64),
		Accent:  strings.TrimSpace(r.PostFormValue("accent")),
		Support: strings.TrimSpace(r.PostFormValue("support")),
		Note:    clip(r.PostFormValue("note"), 280),
	}
	if page.Accent != "" && !accentPattern.MatchString(page.Accent) {
		page.Accent = ""
	}
	if page.Support != "" && !(strings.HasPrefix(page.Support, "https://") || strings.HasPrefix(page.Support, "tg://")) {
		page.Support = ""
	}
	for _, app := range r.PostForm["apps"] {
		for _, known := range pageApps {
			if app == known {
				page.Apps = append(page.Apps, app)
			}
		}
	}
	_ = s.store.UpdateProject(p.ID, si.user.Email, "page.saved", "", func(p *store.Project) { p.Page = page })
	http.Redirect(w, r, "/cloud/p/"+p.ID+"?saved=1#page", http.StatusSeeOther)
}

func (s *Server) createToken(w http.ResponseWriter, r *http.Request) {
	p, ok := s.owned(w, r)
	if !ok {
		return
	}
	si := current(r)
	name := clip(r.PostFormValue("name"), 40)
	if name == "" {
		name = "token"
	}
	secret, _, err := s.store.AddToken(p.ID, name, si.user.Email)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	d := s.projectView(r, p)
	d.NewToken = secret
	s.render(w, r, http.StatusOK, "project", view{Title: p.Name, User: si.user, CSRF: si.session.CSRF, Data: d})
}

func (s *Server) revokeToken(w http.ResponseWriter, r *http.Request) {
	p, ok := s.owned(w, r)
	if !ok {
		return
	}
	_ = s.store.DropToken(p.ID, r.PathValue("tid"), current(r).user.Email)
	http.Redirect(w, r, "/cloud/p/"+p.ID+"#tokens", http.StatusSeeOther)
}

func (s *Server) deleteProject(w http.ResponseWriter, r *http.Request) {
	p, ok := s.owned(w, r)
	if !ok {
		return
	}
	if r.PostFormValue("confirm") != p.ID {
		http.Redirect(w, r, "/cloud/p/"+p.ID+"#danger", http.StatusSeeOther)
		return
	}
	_ = s.store.DeleteProject(p.ID, current(r).user.Email)
	s.log.Info("project deleted", "project", p.ID, "by", current(r).user.ID)
	http.Redirect(w, r, "/cloud/", http.StatusSeeOther)
}

type adminData struct {
	Users    []store.User
	Projects []store.Project
}

func (s *Server) admin(w http.ResponseWriter, r *http.Request) {
	si := current(r)
	if !si.user.Admin {
		s.fail(w, r, http.StatusNotFound, "error.notFound")
		return
	}
	s.render(w, r, http.StatusOK, "admin", view{Title: tr(langOf(r), "nav.admin"), User: si.user, CSRF: si.session.CSRF, Data: adminData{Users: s.store.Users(), Projects: s.store.Projects("")}})
}

func (s *Server) adminToggleUser(w http.ResponseWriter, r *http.Request) {
	si := current(r)
	if !si.user.Admin || r.PathValue("uid") == si.user.ID {
		s.fail(w, r, http.StatusNotFound, "error.notFound")
		return
	}
	_ = s.store.UpdateUser(r.PathValue("uid"), func(u *store.User) { u.Disabled = !u.Disabled })
	http.Redirect(w, r, "/cloud/admin", http.StatusSeeOther)
}

func (s *Server) adminToggleProject(w http.ResponseWriter, r *http.Request) {
	si := current(r)
	if !si.user.Admin {
		s.fail(w, r, http.StatusNotFound, "error.notFound")
		return
	}
	_ = s.store.UpdateProject(r.PathValue("id"), si.user.Email, "project.toggled", "admin", func(p *store.Project) { p.Disabled = !p.Disabled })
	http.Redirect(w, r, "/cloud/admin", http.StatusSeeOther)
}

func validKey(key string) bool {
	raw, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(key, "="))
	return err == nil && len(raw) == 32
}

func clip(raw string, max int) string {
	text := strings.TrimSpace(raw)
	runes := []rune(text)
	if len(runes) > max {
		return string(runes[:max])
	}
	return text
}

func atoi(raw string) int {
	n := 0
	for _, c := range raw {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
		if n > 1<<40 {
			return 0
		}
	}
	return n
}
