package web

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/Makhkets/commy/cloud/internal/manifest"
	"github.com/Makhkets/commy/cloud/internal/store"
)

type fixture struct {
	t    *testing.T
	srv  *httptest.Server
	st   *store.Store
	http *http.Client
	csrf string
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "cloud.json"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := New(Config{BaseURL: "http://cloud.example.test"}, st)
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(s.Handler())
	t.Cleanup(srv.Close)
	jar, _ := cookiejar.New(nil)
	return &fixture{t: t, srv: srv, st: st, http: &http.Client{Jar: jar, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}

func (f *fixture) post(path string, form url.Values, origin string) *http.Response {
	f.t.Helper()
	req, _ := http.NewRequest(http.MethodPost, f.srv.URL+path, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	resp, err := f.http.Do(req)
	if err != nil {
		f.t.Fatal(err)
	}
	return resp
}

func (f *fixture) get(path string) (int, string) {
	f.t.Helper()
	resp, err := f.http.Get(f.srv.URL + path)
	if err != nil {
		f.t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(body)
}

var csrfField = regexp.MustCompile(`name="csrf" value="([^"]+)"`)

// signUp registers the first operator, who is the admin, and keeps the
// session's CSRF token.
func (f *fixture) signUp() {
	resp := f.post("/cloud/signup", url.Values{"email": {"op@example.com"}, "password": {"long-enough-1"}, "password2": {"long-enough-1"}}, f.srv.URL)
	if resp.StatusCode != http.StatusSeeOther {
		f.t.Fatalf("signup: %d", resp.StatusCode)
	}
	_, body := f.get("/cloud/")
	m := csrfField.FindStringSubmatch(body)
	if m == nil {
		f.t.Fatal("no csrf on the projects page")
	}
	f.csrf = m[1]
}

func key(seed string) ed25519.PrivateKey {
	sum := sha256.Sum256([]byte(seed))
	return ed25519.NewKeyFromSeed(sum[:])
}

func signed(t *testing.T, priv ed25519.PrivateKey, seq int64, origin string) string {
	t.Helper()
	compact, err := manifest.Sign(manifest.Manifest{ID: "axm", Seq: seq, IssuedAt: 1, Origin: origin, Rendezvous: []string{"https://cloud.example.test/r/axm"}}, priv)
	if err != nil {
		t.Fatal(err)
	}
	return compact
}

func (f *fixture) createProject(priv ed25519.PrivateKey) {
	resp := f.post("/cloud/projects", url.Values{"csrf": {f.csrf}, "id": {"axm"}, "name": {"AXM"}, "key": {manifest.Encode(priv.Public().(ed25519.PublicKey))}}, f.srv.URL)
	if resp.StatusCode != http.StatusSeeOther {
		f.t.Fatalf("create project: %d", resp.StatusCode)
	}
}

func TestAPostWithoutTheSessionsTokenOrFromElsewhereIsRefused(t *testing.T) {
	f := newFixture(t)
	f.signUp()
	if r := f.post("/cloud/projects", url.Values{"id": {"x"}}, f.srv.URL); r.StatusCode != http.StatusForbidden {
		t.Fatalf("missing csrf: %d", r.StatusCode)
	}
	if r := f.post("/cloud/projects", url.Values{"csrf": {f.csrf}, "id": {"x"}}, "https://evil.example"); r.StatusCode != http.StatusForbidden {
		t.Fatalf("cross origin: %d", r.StatusCode)
	}
	if r := f.post("/cloud/projects", url.Values{"csrf": {f.csrf}, "id": {"x"}}, ""); r.StatusCode != http.StatusForbidden {
		t.Fatalf("no origin: %d", r.StatusCode)
	}
}

func TestSignupClosesAfterTheAdminUnlessOpen(t *testing.T) {
	f := newFixture(t)
	f.signUp()
	other := &http.Client{}
	req, _ := http.NewRequest(http.MethodPost, f.srv.URL+"/cloud/signup", strings.NewReader("email=b%40example.com&password=long-enough-1&password2=long-enough-1"))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", f.srv.URL)
	resp, _ := other.Do(req)
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("second signup: %d", resp.StatusCode)
	}
}

func TestPublishServeAndRefuse(t *testing.T) {
	f := newFixture(t)
	f.signUp()
	priv := key("operator")
	f.createProject(priv)
	first := signed(t, priv, 1, "https://sub.example.com")
	if r := f.post("/cloud/p/axm/manifests", url.Values{"csrf": {f.csrf}, "manifest": {first}}, f.srv.URL); r.StatusCode != http.StatusSeeOther {
		t.Fatalf("publish: %d", r.StatusCode)
	}
	for name, compact := range map[string]string{
		"replay":       first,
		"stranger key": signed(t, key("stranger"), 2, "https://evil.example"),
		"garbage":      "v1.nope.nope",
	} {
		if r := f.post("/cloud/p/axm/manifests", url.Values{"csrf": {f.csrf}, "manifest": {compact}}, f.srv.URL); r.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: %d", name, r.StatusCode)
		}
	}
	req, _ := http.NewRequest(http.MethodGet, f.srv.URL+"/r/axm", nil)
	req.Header.Set("User-Agent", "Commy/0.1.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if strings.TrimSpace(string(body)) != first {
		t.Fatalf("meeting point served %q", body)
	}
	if stats := f.st.Stats("axm", 1); stats[0].Visits != 1 || stats[0].Versions["0.1.0"] != 1 {
		t.Fatalf("visit not counted: %+v", stats)
	}
	if code, _ := f.get("/r/unknown"); code != http.StatusNotFound {
		t.Fatalf("unknown project: %d", code)
	}
}

func TestAPIIsScopedToItsProject(t *testing.T) {
	f := newFixture(t)
	f.signUp()
	priv := key("operator")
	f.createProject(priv)
	secret, _, err := f.st.AddToken("axm", "ci", "test")
	if err != nil {
		t.Fatal(err)
	}
	call := func(method, path, token, body string) (int, map[string]any) {
		req, _ := http.NewRequest(method, f.srv.URL+path, strings.NewReader(body))
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var out map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&out)
		return resp.StatusCode, out
	}
	if code, _ := call("GET", "/api/v1/projects/axm", "", ""); code != http.StatusUnauthorized {
		t.Fatalf("no token: %d", code)
	}
	if code, _ := call("GET", "/api/v1/projects/other", secret, ""); code != http.StatusUnauthorized {
		t.Fatalf("other project: %d", code)
	}
	payload, _ := json.Marshal(map[string]string{"manifest": signed(t, priv, 5, "https://sub.example.com")})
	if code, out := call("POST", "/api/v1/projects/axm/manifests", secret, string(payload)); code != http.StatusCreated || out["seq"].(float64) != 5 {
		t.Fatalf("publish: %d %v", code, out)
	}
	if code, out := call("POST", "/api/v1/projects/axm/manifests", secret, string(payload)); code != http.StatusUnprocessableEntity || out["error"] == "" {
		t.Fatalf("replay: %d %v", code, out)
	}
	if code, out := call("GET", "/api/v1/projects/axm", secret, ""); code != http.StatusOK || out["latest"] == nil {
		t.Fatalf("project: %d %v", code, out)
	}
}

func TestPagesAndHeaders(t *testing.T) {
	f := newFixture(t)
	f.signUp()
	f.createProject(key("operator"))
	code, body := f.get("/s/axm")
	if code != http.StatusOK || !strings.Contains(body, "AXM") || !strings.Contains(body, "/static/page.js") {
		t.Fatalf("subscription page: %d", code)
	}
	resp, _ := http.Get(f.srv.URL + "/s/axm")
	if csp := resp.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") {
		t.Fatalf("csp %q", csp)
	}
	if resp.Header.Get("Referrer-Policy") != "same-origin" {
		t.Fatal("referrer policy")
	}
	if code, _ := f.get("/cloud/p/nope"); code != http.StatusNotFound {
		t.Fatalf("missing project: %d", code)
	}
}

func TestPasswords(t *testing.T) {
	hash, err := hashPassword("correct horse")
	if err != nil {
		t.Fatal(err)
	}
	if !checkPassword(hash, "correct horse") || checkPassword(hash, "wrong") || checkPassword("garbage", "x") {
		t.Fatal("password check")
	}
}
