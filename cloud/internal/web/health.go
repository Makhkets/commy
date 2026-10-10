package web

import (
	"context"
	"net/http"
	"time"

	"github.com/Makhkets/commy/cloud/internal/manifest"
	"github.com/Makhkets/commy/cloud/internal/store"
)

// healthClient follows no redirects: any answer at all means the address
// is reachable from here, which is all the dashboard claims.
var healthClient = &http.Client{
	Timeout: 10 * time.Second,
	CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

// RunHealth checks every project's addresses every interval until ctx ends,
// and flushes the visit counters on the same beat.
func (s *Server) RunHealth(ctx context.Context, interval time.Duration) {
	tick := time.NewTicker(interval)
	defer tick.Stop()
	for {
		for _, p := range s.store.Projects("") {
			if ctx.Err() != nil {
				return
			}
			s.checkProject(p.ID)
		}
		if err := s.store.Flush(); err != nil {
			s.log.Error("flush", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

// checkProject asks the origin and each mirror of the latest release.
func (s *Server) checkProject(id string) {
	latest, err := s.store.Latest(id)
	if err != nil {
		return
	}
	signed, err := manifest.Parse(latest.Compact)
	if err != nil {
		return
	}
	targets := append([]string{signed.Manifest.Origin}, signed.Manifest.Mirrors...)
	for _, target := range targets {
		s.store.SetHealth(id, probe(target))
	}
}

func probe(target string) store.Health {
	h := store.Health{URL: target, Checked: time.Now().UTC()}
	req, err := http.NewRequest(http.MethodGet, target+"/", nil)
	if err != nil {
		h.Error = err.Error()
		return h
	}
	req.Header.Set("User-Agent", "CommyCloud-health/1")
	start := time.Now()
	resp, err := healthClient.Do(req)
	if err != nil {
		h.Error = shorten(err.Error())
		return h
	}
	resp.Body.Close()
	h.Up = true
	h.Status = resp.StatusCode
	h.Latency = time.Since(start).Milliseconds()
	return h
}

func shorten(s string) string {
	if len(s) > 120 {
		return s[:120] + "…"
	}
	return s
}
