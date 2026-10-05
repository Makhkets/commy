package web

import (
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/Makhkets/commy/cloud/internal/store"
)

const sessionTTL = 30 * 24 * time.Hour

type authData struct {
	Email  string
	Signup bool
	Open   bool
}

func (s *Server) signupOpen() bool {
	return s.cfg.OpenSignup || len(s.store.Users()) == 0
}

func (s *Server) loginForm(w http.ResponseWriter, r *http.Request) {
	s.render(w, r, http.StatusOK, "auth", view{Title: tr(langOf(r), "auth.login"), Data: authData{Open: s.signupOpen()}})
}

func (s *Server) signupForm(w http.ResponseWriter, r *http.Request) {
	s.render(w, r, http.StatusOK, "auth", view{Title: tr(langOf(r), "auth.signup"), Data: authData{Signup: true, Open: s.signupOpen()}})
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	lang := langOf(r)
	email := normaliseEmail(r.PostFormValue("email"))
	data := authData{Email: email, Open: s.signupOpen()}
	if !s.sameOrigin(r) {
		s.render(w, r, http.StatusForbidden, "auth", view{Title: tr(lang, "auth.login"), Error: tr(lang, "error.csrf"), Data: data})
		return
	}
	if !s.authRate.allow(s.clientIP(r)) {
		s.render(w, r, http.StatusTooManyRequests, "auth", view{Title: tr(lang, "auth.login"), Error: tr(lang, "auth.slow"), Data: data})
		return
	}
	user, err := s.store.UserByEmail(email)
	// A missing user is checked against a fixed hash, so the answer takes as
	// long as for a wrong password and does not say which e-mails exist.
	stored := dummyHash
	if err == nil {
		stored = user.PassHash
	}
	if !checkPassword(stored, r.PostFormValue("password")) || err != nil || user.Disabled {
		s.render(w, r, http.StatusUnauthorized, "auth", view{Title: tr(lang, "auth.login"), Error: tr(lang, "auth.bad"), Data: data})
		return
	}
	s.startSession(w, r, user)
}

func (s *Server) signup(w http.ResponseWriter, r *http.Request) {
	lang := langOf(r)
	email := normaliseEmail(r.PostFormValue("email"))
	data := authData{Email: email, Signup: true, Open: s.signupOpen()}
	page := func(status int, key string) {
		s.render(w, r, status, "auth", view{Title: tr(lang, "auth.signup"), Error: tr(lang, key), Data: data})
	}
	if !s.sameOrigin(r) {
		page(http.StatusForbidden, "error.csrf")
		return
	}
	if !s.authRate.allow(s.clientIP(r)) {
		page(http.StatusTooManyRequests, "auth.slow")
		return
	}
	if !s.signupOpen() {
		page(http.StatusForbidden, "auth.closed")
		return
	}
	password := r.PostFormValue("password")
	if _, err := mail.ParseAddress(email); err != nil || len(email) > 254 {
		page(http.StatusBadRequest, "auth.bad")
		return
	}
	if len([]rune(password)) < 10 || len(password) > 1024 || password != r.PostFormValue("password2") {
		page(http.StatusBadRequest, "auth.weak")
		return
	}
	hash, err := hashPassword(password)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	user, err := s.store.AddUser(email, hash)
	if errors.Is(err, store.ErrExists) {
		page(http.StatusConflict, "auth.exists")
		return
	}
	if err != nil {
		s.log.Error("signup", "err", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	s.log.Info("signup", "user", user.ID, "admin", user.Admin)
	s.startSession(w, r, user)
}

func (s *Server) startSession(w http.ResponseWriter, r *http.Request, user *store.User) {
	token, sess, err := s.store.AddSession(user.ID, sessionTTL)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	s.setSession(w, token, sess.Expires)
	http.Redirect(w, r, "/cloud/", http.StatusSeeOther)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	_ = s.store.DropSession(current(r).token)
	s.setSession(w, "", time.Unix(0, 0))
	http.Redirect(w, r, "/cloud/login", http.StatusSeeOther)
}

func normaliseEmail(raw string) string { return strings.ToLower(strings.TrimSpace(raw)) }

// dummyHash is a valid hash of a random password, for unknown users.
var dummyHash = func() string {
	h, _ := hashPassword(store.NewID(16))
	return h
}()
