// Package web is Commy Cloud's HTTP side: the meeting points clients ask,
// the white-label subscription pages, the operators' dashboard and API, and
// the public documentation site.
package web

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/Makhkets/commy/cloud/internal/store"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed static
var staticFS embed.FS

// Config is what the server is told at start.
type Config struct {
	// BaseURL is the public address, e.g. https://commy.makhkets.ru.
	BaseURL string
	// OpenSignup lets anyone create an account; off, only the admin can
	// (the first account is always allowed: it becomes the admin).
	OpenSignup bool
	// TrustProxy reads the client address from X-Forwarded-For, for a
	// server behind Caddy. Off, the socket's address is used.
	TrustProxy bool
	// MaxProjects per account; 0 means 10.
	MaxProjects int
	// Site serves the documentation and landing pages, when set.
	Site http.Handler
	// Logger, or slog.Default.
	Logger *slog.Logger
}

// Server holds the state of the running service.
type Server struct {
	cfg      Config
	store    *store.Store
	tmpl     map[string]*template.Template
	log      *slog.Logger
	authRate *limiter
	pubRate  *limiter
	apiRate  *limiter
	secure   bool
	mux      *http.ServeMux
}

// New builds the server.
func New(cfg Config, st *store.Store) (*Server, error) {
	if cfg.MaxProjects <= 0 {
		cfg.MaxProjects = 10
	}
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	cfg.BaseURL = strings.TrimRight(cfg.BaseURL, "/")
	s := &Server{
		cfg:      cfg,
		store:    st,
		log:      cfg.Logger,
		authRate: newLimiter(10, 10),
		pubRate:  newLimiter(60, 30),
		apiRate:  newLimiter(120, 60),
		secure:   strings.HasPrefix(cfg.BaseURL, "https://"),
	}
	if err := s.loadTemplates(); err != nil {
		return nil, err
	}
	s.routes()
	return s, nil
}

func (s *Server) loadTemplates() error {
	funcs := template.FuncMap{
		"t": func(lang, key string) string { return tr(lang, key) },
		"tf": func(lang, key string, args ...any) string {
			return fmt.Sprintf(tr(lang, key), args...)
		},
		"date": func(t time.Time) string {
			if t.IsZero() {
				return "—"
			}
			return t.UTC().Format("2006-01-02 15:04 UTC")
		},
		"join": strings.Join,
		"has": func(list []string, v string) bool {
			for _, item := range list {
				if item == v {
					return true
				}
			}
			return false
		},
		"host": func(raw string) string {
			if u, err := url.Parse(raw); err == nil && u.Host != "" {
				return u.Host
			}
			return raw
		},
		"pct": func(v, max int) int {
			if max <= 0 {
				return 0
			}
			return v * 100 / max
		},
	}
	pages, err := fs.Glob(templateFS, "templates/*.html")
	if err != nil {
		return err
	}
	s.tmpl = map[string]*template.Template{}
	for _, page := range pages {
		name := strings.TrimSuffix(strings.TrimPrefix(page, "templates/"), ".html")
		if name == "layout" {
			continue
		}
		t, err := template.New("layout.html").Funcs(funcs).ParseFS(templateFS, "templates/layout.html", page)
		if err != nil {
			return fmt.Errorf("%s: %w", page, err)
		}
		s.tmpl[name] = t
	}
	return nil
}

// Handler is the whole service, with its security headers.
func (s *Server) Handler() http.Handler { return s.headers(s.mux) }

func (s *Server) routes() {
	mux := http.NewServeMux()
	static, _ := fs.Sub(staticFS, "static")
	mux.Handle("GET /static/", http.StripPrefix("/static/", cacheFor(24*time.Hour, http.FileServerFS(static))))
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprintln(w, "ok")
	})

	// Clients.
	mux.HandleFunc("GET /r/{id}", s.rendezvous)
	mux.HandleFunc("GET /s/{id}", s.subscriptionPage)

	// Dashboard.
	mux.HandleFunc("GET /cloud/login", s.loginForm)
	mux.HandleFunc("POST /cloud/login", s.login)
	mux.HandleFunc("GET /cloud/signup", s.signupForm)
	mux.HandleFunc("POST /cloud/signup", s.signup)
	mux.HandleFunc("POST /cloud/logout", s.signedIn(s.logout))
	mux.HandleFunc("GET /cloud/{$}", s.signedIn(s.projects))
	mux.HandleFunc("GET /cloud", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/cloud/", http.StatusFound)
	})
	mux.HandleFunc("POST /cloud/projects", s.signedIn(s.createProject))
	mux.HandleFunc("GET /cloud/p/{id}", s.signedIn(s.project))
	mux.HandleFunc("POST /cloud/p/{id}/manifests", s.signedIn(s.publishFromDashboard))
	mux.HandleFunc("POST /cloud/p/{id}/page", s.signedIn(s.savePage))
	mux.HandleFunc("POST /cloud/p/{id}/tokens", s.signedIn(s.createToken))
	mux.HandleFunc("POST /cloud/p/{id}/tokens/{tid}/revoke", s.signedIn(s.revokeToken))
	mux.HandleFunc("POST /cloud/p/{id}/delete", s.signedIn(s.deleteProject))
	mux.HandleFunc("GET /cloud/admin", s.signedIn(s.admin))
	mux.HandleFunc("POST /cloud/admin/users/{uid}", s.signedIn(s.adminToggleUser))
	mux.HandleFunc("POST /cloud/admin/projects/{id}", s.signedIn(s.adminToggleProject))
	mux.HandleFunc("GET /cloud/lang/{lang}", s.setLang)

	// API.
	mux.HandleFunc("GET /api/v1/projects/{id}", s.api(s.apiProject))
	mux.HandleFunc("GET /api/v1/projects/{id}/manifests", s.api(s.apiReleases))
	mux.HandleFunc("POST /api/v1/projects/{id}/manifests", s.api(s.apiPublish))
	mux.HandleFunc("GET /api/v1/projects/{id}/stats", s.api(s.apiStats))

	if s.cfg.Site != nil {
		mux.Handle("/", s.cfg.Site)
	}
	s.mux = mux
}

// headers sets the policy every answer carries.
func (s *Server) headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "same-origin")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), interest-cohort=()")
		h.Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
		if s.secure {
			h.Set("Strict-Transport-Security", "max-age=31536000")
		}
		next.ServeHTTP(w, r)
	})
}

func cacheFor(d time.Duration, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", fmt.Sprintf("public, max-age=%d", int(d.Seconds())))
		next.ServeHTTP(w, r)
	})
}

// clientIP is the address the request came from; behind Caddy, the last
// hop Caddy itself appended to X-Forwarded-For.
func (s *Server) clientIP(r *http.Request) string {
	if s.cfg.TrustProxy {
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			parts := strings.Split(fwd, ",")
			return strings.TrimSpace(parts[len(parts)-1])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// ---- rendering ----

type view struct {
	Lang    string
	Title   string
	User    *store.User
	CSRF    string
	Base    string
	Flash   string
	Error   string
	Data    any
	Section string
}

func (s *Server) render(w http.ResponseWriter, r *http.Request, status int, name string, v view) {
	if v.Lang == "" {
		v.Lang = langOf(r)
	}
	v.Base = s.cfg.BaseURL
	t, ok := s.tmpl[name]
	if !ok {
		http.Error(w, "no template "+name, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if err := t.Execute(w, v); err != nil {
		s.log.Error("render", "template", name, "err", err)
	}
}

func (s *Server) fail(w http.ResponseWriter, r *http.Request, status int, key string) {
	s.render(w, r, status, "error", view{Title: tr(langOf(r), key), Error: tr(langOf(r), key)})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

// ---- sessions ----

const sessionCookie = "cc_session"

type sessionKey struct{}

type signedIn struct {
	user    *store.User
	session *store.Session
	token   string
}

// signedIn requires a live session, and for a POST the session's CSRF token
// and a same-origin request.
func (s *Server) signedIn(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		c, err := r.Cookie(sessionCookie)
		if err != nil {
			s.toLogin(w, r)
			return
		}
		sess, err := s.store.Session(c.Value)
		if err != nil {
			s.toLogin(w, r)
			return
		}
		user, err := s.store.User(sess.UserID)
		if err != nil || user.Disabled {
			s.toLogin(w, r)
			return
		}
		if r.Method == http.MethodPost {
			if !s.sameOrigin(r) || r.PostFormValue("csrf") != sess.CSRF {
				s.fail(w, r, http.StatusForbidden, "error.csrf")
				return
			}
		}
		ctx := context.WithValue(r.Context(), sessionKey{}, &signedIn{user: user, session: sess, token: c.Value})
		next(w, r.WithContext(ctx))
	}
}

func current(r *http.Request) *signedIn {
	si, _ := r.Context().Value(sessionKey{}).(*signedIn)
	return si
}

func (s *Server) toLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		http.Redirect(w, r, "/cloud/login", http.StatusFound)
		return
	}
	s.fail(w, r, http.StatusForbidden, "error.forbidden")
}

// sameOrigin checks Origin (or Referer) against the host the request was
// sent to: a form posted from another site is refused even with a cookie.
func (s *Server) sameOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		origin = r.Header.Get("Referer")
	}
	if origin == "" {
		return false
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return u.Host == r.Host
}

func (s *Server) setSession(w http.ResponseWriter, token string, expires time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    token,
		Path:     "/",
		Expires:  expires,
		HttpOnly: true,
		Secure:   s.secure,
		SameSite: http.SameSiteLaxMode,
	})
}

func (s *Server) setLang(w http.ResponseWriter, r *http.Request) {
	lang := r.PathValue("lang")
	ok := false
	for _, l := range languages {
		ok = ok || l == lang
	}
	if ok {
		http.SetCookie(w, &http.Cookie{Name: "lang", Value: lang, Path: "/", MaxAge: 365 * 24 * 3600, SameSite: http.SameSiteLaxMode, Secure: s.secure})
	}
	back := "/cloud/"
	if ref := r.Header.Get("Referer"); ref != "" {
		if u, err := url.Parse(ref); err == nil && u.Host == r.Host {
			back = u.RequestURI()
		}
	}
	http.Redirect(w, r, back, http.StatusFound)
}

var errBadForm = errors.New("bad form")
