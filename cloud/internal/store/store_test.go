package store

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func openTemp(t *testing.T) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "cloud.json")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	return s, path
}

func TestFirstUserIsAdminAndEmailsAreUnique(t *testing.T) {
	s, _ := openTemp(t)
	first, err := s.AddUser("a@example.com", "h")
	if err != nil || !first.Admin {
		t.Fatalf("first user: %+v %v", first, err)
	}
	second, _ := s.AddUser("b@example.com", "h")
	if second.Admin {
		t.Fatal("second user must not be admin")
	}
	if _, err := s.AddUser("a@example.com", "h"); !errors.Is(err, ErrExists) {
		t.Fatalf("duplicate e-mail: %v", err)
	}
}

func TestReleasesOnlyMoveForward(t *testing.T) {
	s, _ := openTemp(t)
	s.AddProject(Project{ID: "p", OwnerID: "u", Name: "P", Key: "k1"}, "u")
	if err := s.Publish("p", Release{Seq: 2, Origin: "https://a"}, "k1", "k2"); err != nil {
		t.Fatal(err)
	}
	if err := s.Publish("p", Release{Seq: 2}, "k1", ""); !errors.Is(err, ErrStale) {
		t.Fatalf("same seq: %v", err)
	}
	if err := s.Publish("p", Release{Seq: 3, Origin: "https://b"}, "k2", ""); err != nil {
		t.Fatal(err)
	}
	latest, _ := s.Latest("p")
	p, _ := s.Project("p")
	if latest.Seq != 3 || p.Key != "k2" || p.NextKey != "" {
		t.Fatalf("latest %+v project %+v", latest, p)
	}
	if got := s.Releases("p"); got[0].Seq != 3 || got[1].Seq != 2 {
		t.Fatalf("order %+v", got)
	}
	if ev := s.Events("p"); len(ev) != 3 || ev[0].Action != "manifest.published" {
		t.Fatalf("events %+v", ev)
	}
}

func TestStateSurvivesReopenAndIsPrivate(t *testing.T) {
	s, path := openTemp(t)
	s.AddProject(Project{ID: "p", OwnerID: "u", Name: "P", Key: "k"}, "u")
	secret, _, _ := s.AddToken("p", "ci", "u")
	again, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := again.Project("p"); err != nil {
		t.Fatal(err)
	}
	if tok, err := again.TokenBySecret(secret); err != nil || tok.ProjectID != "p" {
		t.Fatalf("token: %v %v", tok, err)
	}
	raw, _ := os.ReadFile(path)
	if strings.Contains(string(raw), secret) {
		t.Fatal("token secret stored in the clear")
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", info.Mode())
	}
}

func TestVisitorsAreCountedOnceADayAndNeverStored(t *testing.T) {
	s, path := openTemp(t)
	now := time.Date(2026, 10, 5, 12, 0, 0, 0, time.UTC)
	s.SetClock(func() time.Time { return now })
	s.CountVisit("p", "203.0.113.7", "1.0.0")
	s.CountVisit("p", "203.0.113.7", "1.0.0")
	s.CountVisit("p", "198.51.100.1", "0.9.0")
	s.Flush()
	stats := s.Stats("p", 1)
	if stats[0].Visits != 3 || stats[0].Unique != 2 || stats[0].Versions["1.0.0"] != 2 {
		t.Fatalf("stats %+v", stats)
	}
	raw, _ := os.ReadFile(path)
	if strings.Contains(string(raw), "203.0.113.7") {
		t.Fatal("IP address stored")
	}
	now = now.Add(24 * time.Hour)
	s.CountVisit("p", "203.0.113.7", "1.0.0")
	if got := s.Stats("p", 1)[0]; got.Unique != 1 {
		t.Fatalf("next day %+v", got)
	}
}

func TestSessionsExpire(t *testing.T) {
	s, _ := openTemp(t)
	now := time.Date(2026, 10, 5, 12, 0, 0, 0, time.UTC)
	s.SetClock(func() time.Time { return now })
	token, _, _ := s.AddSession("u", time.Hour)
	if _, err := s.Session(token); err != nil {
		t.Fatal(err)
	}
	now = now.Add(2 * time.Hour)
	if _, err := s.Session(token); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expired session: %v", err)
	}
}

// The API sizes the answer by a number from the request; the store holds the
// line itself, whatever the caller checked.
func TestStatsClampsTheNumberOfDays(t *testing.T) {
	s, _ := openTemp(t)
	if got := len(s.Stats("p", 1<<40)); got != MaxStatDays {
		t.Fatalf("huge n: got %d days, want %d", got, MaxStatDays)
	}
	if got := len(s.Stats("p", -5)); got != 0 {
		t.Fatalf("negative n: got %d days, want 0", got)
	}
}
