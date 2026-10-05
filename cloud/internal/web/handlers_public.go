package web

import (
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/Makhkets/commy/cloud/internal/manifest"
	"github.com/Makhkets/commy/cloud/internal/store"
)

// pageApps are the clients a white-label page can offer, each with the
// import link its own subscription page uses (Remnawave's app-config, the
// same list ForeignImportLink reads in the client).
var pageApps = []string{"commy", "happ", "incy", "v2raytun", "hiddify", "streisand", "shadowrocket", "v2rayng", "clashmeta", "singbox"}

var versionPattern = regexp.MustCompile(`(?i)\bcommy/([0-9][0-9A-Za-z.+-]{0,31})`)

// rendezvous serves a project's latest manifest to clients (exception E-4
// on their side, ADR-0019). It is a public, cacheable, signed blob; the
// only thing remembered of the request is a daily counter.
func (s *Server) rendezvous(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	ip := s.clientIP(r)
	if !s.pubRate.allow(ip) {
		w.Header().Set("Retry-After", "60")
		http.Error(w, "slow down", http.StatusTooManyRequests)
		return
	}
	if !manifest.ValidID(id) {
		http.NotFound(w, r)
		return
	}
	p, err := s.store.Project(id)
	if err != nil || p.Disabled {
		http.NotFound(w, r)
		return
	}
	latest, err := s.store.Latest(id)
	if errors.Is(err, store.ErrNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	version := ""
	if m := versionPattern.FindStringSubmatch(r.UserAgent()); m != nil {
		version = m[1]
	}
	s.store.CountVisit(id, ip, version)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	_, _ = w.Write([]byte(latest.Compact + "\n"))
}

type pageData struct {
	Project *store.Project
	Title   string
	Apps    []string
}

// subscriptionPage is the operator's white-label page. The subscription
// address is in the URL fragment, which browsers never send: the page's
// script reads it and builds the buttons, and this server never sees it.
func (s *Server) subscriptionPage(w http.ResponseWriter, r *http.Request) {
	p, err := s.store.Project(r.PathValue("id"))
	if err != nil || p.Disabled {
		s.fail(w, r, http.StatusNotFound, "error.notFound")
		return
	}
	apps := p.Page.Apps
	if len(apps) == 0 {
		apps = pageApps
	}
	title := p.Page.Title
	if strings.TrimSpace(title) == "" {
		title = p.Name
	}
	s.render(w, r, http.StatusOK, "page", view{Title: title, Data: pageData{Project: p, Title: title, Apps: apps}})
}
