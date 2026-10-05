package web

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/Makhkets/commy/cloud/internal/store"
)

type apiKey struct{}

// api requires a bearer token of the project in the path.
func (s *Server) api(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.apiRate.allow(s.clientIP(r)) {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "rate limited"})
			return
		}
		secret, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || secret == "" {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing bearer token"})
			return
		}
		token, err := s.store.TokenBySecret(strings.TrimSpace(secret))
		if err != nil || token.ProjectID != r.PathValue("id") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"})
			return
		}
		p, err := s.store.Project(token.ProjectID)
		if err != nil || p.Disabled {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "project not found"})
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), apiKey{}, struct {
			token   *store.Token
			project *store.Project
		}{token, p})))
	}
}

func apiCaller(r *http.Request) (*store.Token, *store.Project) {
	v := r.Context().Value(apiKey{}).(struct {
		token   *store.Token
		project *store.Project
	})
	return v.token, v.project
}

type apiRelease struct {
	Seq       int64    `json:"seq"`
	Origin    string   `json:"origin"`
	Mirrors   []string `json:"mirrors"`
	Manifest  string   `json:"manifest"`
	Published string   `json:"published"`
}

func releaseJSON(r store.Release) apiRelease {
	return apiRelease{Seq: r.Seq, Origin: r.Origin, Mirrors: r.Mirrors, Manifest: r.Compact, Published: r.Published.UTC().Format("2006-01-02T15:04:05Z")}
}

func (s *Server) apiProject(w http.ResponseWriter, r *http.Request) {
	_, p := apiCaller(r)
	out := map[string]any{
		"id": p.ID, "name": p.Name, "key": p.Key, "next_key": p.NextKey,
		"rendezvous": s.cfg.BaseURL + "/r/" + p.ID,
		"page":       s.cfg.BaseURL + "/s/" + p.ID,
	}
	if latest, err := s.store.Latest(p.ID); err == nil {
		out["latest"] = releaseJSON(*latest)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) apiReleases(w http.ResponseWriter, r *http.Request) {
	_, p := apiCaller(r)
	out := []apiRelease{}
	for _, rel := range s.store.Releases(p.ID) {
		out = append(out, releaseJSON(rel))
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) apiPublish(w http.ResponseWriter, r *http.Request) {
	token, p := apiCaller(r)
	var body struct {
		Manifest string `json:"manifest"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 16<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body must be {\"manifest\": \"v1....\"}"})
		return
	}
	signed, problem := s.publish(p, body.Manifest, "token:"+token.Name, "en")
	if problem != "" {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": problem})
		return
	}
	go s.checkProject(p.ID)
	latest, _ := s.store.Latest(p.ID)
	_ = signed
	writeJSON(w, http.StatusCreated, releaseJSON(*latest))
}

func (s *Server) apiStats(w http.ResponseWriter, r *http.Request) {
	_, p := apiCaller(r)
	days, err := strconv.Atoi(r.URL.Query().Get("days"))
	if err != nil || days < 1 || days > 365 {
		days = 30
	}
	type day struct {
		Date     string         `json:"date"`
		Visits   int            `json:"visits"`
		Unique   int            `json:"unique"`
		Versions map[string]int `json:"versions"`
	}
	out := []day{}
	for _, d := range s.store.Stats(p.ID, days) {
		out = append(out, day{Date: d.Date, Visits: d.Visits, Unique: d.Unique, Versions: d.Versions})
	}
	writeJSON(w, http.StatusOK, out)
}
