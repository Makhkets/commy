package site

import (
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

var href = regexp.MustCompile(`href="(/[^"#]*)`)

// Every page of both languages renders, and every link inside the site
// lands on a page that exists.
func TestEveryPageAndEveryInternalLink(t *testing.T) {
	s, err := New("https://commy.example.test")
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(s)
	defer srv.Close()
	get := func(path string) (int, string) {
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, string(body)
	}
	seen := map[string]bool{}
	queue := []string{"/", "/en/"}
	for len(queue) > 0 {
		path := queue[0]
		queue = queue[1:]
		if seen[path] {
			continue
		}
		seen[path] = true
		code, body := get(path)
		if code != http.StatusOK {
			t.Errorf("%s: %d", path, code)
			continue
		}
		for _, m := range href.FindAllStringSubmatch(body, -1) {
			link := m[1]
			if strings.HasPrefix(link, "/static/") || strings.HasPrefix(link, "/cloud") {
				continue
			}
			queue = append(queue, link)
		}
	}
	for _, lang := range Languages {
		for slug := range s.pages[lang] {
			if !seen[docURL(lang, slug)] {
				t.Errorf("page %s/%s is linked from nowhere", lang, slug)
			}
		}
	}
	if code, _ := get("/docs/no-such-page/"); code != http.StatusNotFound {
		t.Errorf("missing page: %d", code)
	}
	if len(seen) < 30 {
		t.Errorf("only %d pages reached", len(seen))
	}
}
