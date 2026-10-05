// Package site is the public face of Commy at the Cloud's address: the
// landing page and the documentation, in Russian and English.
//
// Pages are Markdown files embedded in the binary and rendered once at
// start; the navigation is content/nav.json. No build step, no Node, no
// third-party request from the visitor's browser — the same promise the app
// makes, kept by its website.
package site

import (
	"bytes"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io/fs"
	"net/http"
	"path"
	"regexp"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer/html"
)

//go:embed content
var contentFS embed.FS

//go:embed templates/*.html
var templateFS embed.FS

// Languages, the first being the default at "/".
var Languages = []string{"ru", "en"}

type navSection struct {
	Title string   `json:"title"`
	Pages []string `json:"pages"`
}

// Page is one rendered document.
type Page struct {
	Lang    string
	Slug    string
	Title   string
	Summary string
	HTML    template.HTML
	Text    string
	Prev    *Page
	Next    *Page
}

// Site serves the landing page and the documentation.
type Site struct {
	base   string
	pages  map[string]map[string]*Page
	nav    map[string][]navSection
	tmpl   *template.Template
	search map[string][]byte
}

var frontMatter = regexp.MustCompile(`(?s)\A---\n(.*?)\n---\n`)

// New renders every page.
func New(base string) (*Site, error) {
	md := goldmark.New(
		goldmark.WithExtensions(extension.GFM, extension.Typographer),
		goldmark.WithParserOptions(parser.WithAutoHeadingID()),
		goldmark.WithRendererOptions(html.WithUnsafe()),
	)
	s := &Site{
		base:   strings.TrimRight(base, "/"),
		pages:  map[string]map[string]*Page{},
		nav:    map[string][]navSection{},
		search: map[string][]byte{},
	}
	for _, lang := range Languages {
		s.pages[lang] = map[string]*Page{}
		raw, err := fs.ReadFile(contentFS, "content/"+lang+"/nav.json")
		if err != nil {
			return nil, err
		}
		var nav []navSection
		if err := json.Unmarshal(raw, &nav); err != nil {
			return nil, fmt.Errorf("%s nav: %w", lang, err)
		}
		s.nav[lang] = nav
		var order []*Page
		for _, section := range nav {
			for _, slug := range section.Pages {
				file := "content/" + lang + "/" + slug + ".md"
				if slug == "" {
					file = "content/" + lang + "/index.md"
				}
				src, err := fs.ReadFile(contentFS, file)
				if err != nil {
					return nil, fmt.Errorf("%s: %w", file, err)
				}
				p := &Page{Lang: lang, Slug: slug}
				body := src
				if m := frontMatter.FindSubmatch(src); m != nil {
					for _, line := range strings.Split(string(m[1]), "\n") {
						key, value, ok := strings.Cut(line, ":")
						if !ok {
							continue
						}
						switch strings.TrimSpace(key) {
						case "title":
							p.Title = strings.TrimSpace(value)
						case "summary":
							p.Summary = strings.TrimSpace(value)
						}
					}
					body = src[len(m[0]):]
				}
				body = bytes.ReplaceAll(body, []byte("{{BASE}}"), []byte(s.base))
				var out bytes.Buffer
				if err := md.Convert(body, &out); err != nil {
					return nil, fmt.Errorf("%s: %w", file, err)
				}
				p.HTML = template.HTML(out.String())
				p.Text = plain(string(body))
				s.pages[lang][slug] = p
				order = append(order, p)
			}
		}
		for i, p := range order {
			if i > 0 {
				p.Prev = order[i-1]
			}
			if i < len(order)-1 {
				p.Next = order[i+1]
			}
		}
		type entry struct {
			URL, Title, Text string
		}
		var index []entry
		for _, p := range order {
			text := p.Text
			if len(text) > 4000 {
				text = text[:4000]
			}
			index = append(index, entry{URL: docURL(lang, p.Slug), Title: p.Title, Text: text})
		}
		s.search[lang], _ = json.Marshal(index)
	}
	funcs := template.FuncMap{
		"docURL": docURL,
		"home": func(lang string) string {
			if lang == Languages[0] {
				return "/"
			}
			return "/" + lang + "/"
		},
		"tr": func(lang, key string) template.HTML { return template.HTML(texts[lang][key]) },
	}
	t, err := template.New("").Funcs(funcs).ParseFS(templateFS, "templates/*.html")
	if err != nil {
		return nil, err
	}
	s.tmpl = t
	return s, nil
}

func docURL(lang, slug string) string {
	prefix := "/docs/"
	if lang != Languages[0] {
		prefix = "/" + lang + "/docs/"
	}
	if slug == "" {
		return prefix
	}
	return prefix + slug + "/"
}

var mdNoise = regexp.MustCompile("[#*`>|\\[\\]()_-]+")

func plain(md string) string {
	return strings.Join(strings.Fields(mdNoise.ReplaceAllString(md, " ")), " ")
}

type pageView struct {
	Lang     string
	Other    string
	OtherURL string
	Page     *Page
	Nav      []navSection
	Pages    map[string]*Page
	Title    string
	Base     string
	Download string
}

// Release downloads, for every button that says "download".
const downloadURL = "https://github.com/Makhkets/Commy/releases/latest"

func (s *Site) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p := path.Clean(r.URL.Path)
	lang := Languages[0]
	for _, l := range Languages[1:] {
		if p == "/"+l || strings.HasPrefix(p, "/"+l+"/") {
			lang = l
			p = strings.TrimPrefix(p, "/"+l)
			if p == "" {
				p = "/"
			}
		}
	}
	switch {
	case p == "/search.json":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		_, _ = w.Write(s.search[lang])
		return
	case p == "/":
		s.render(w, "landing", s.view(lang, nil, "/"))
		return
	case p == "/docs" || strings.HasPrefix(p, "/docs/"):
		if !strings.HasSuffix(r.URL.Path, "/") {
			http.Redirect(w, r, r.URL.Path+"/", http.StatusMovedPermanently)
			return
		}
		slug := strings.Trim(strings.TrimPrefix(p, "/docs"), "/")
		page, ok := s.pages[lang][slug]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			s.render(w, "notfound", s.view(lang, nil, "/"))
			return
		}
		s.render(w, "doc", s.view(lang, page, "/docs/"+slug))
		return
	}
	w.WriteHeader(http.StatusNotFound)
	s.render(w, "notfound", s.view(lang, nil, "/"))
}

func (s *Site) view(lang string, page *Page, rest string) pageView {
	other := Languages[1]
	if lang != Languages[0] {
		other = Languages[0]
	}
	otherURL := rest
	if other != Languages[0] {
		otherURL = "/" + other + rest
	}
	if strings.HasPrefix(rest, "/docs/") && rest != "/docs/" {
		otherURL = strings.TrimSuffix(otherURL, "/") + "/"
	}
	v := pageView{Lang: lang, Other: other, OtherURL: otherURL, Page: page, Nav: s.nav[lang], Pages: s.pages[lang], Base: s.base, Download: downloadURL}
	if page != nil {
		v.Title = page.Title
	}
	return v
}

func (s *Site) render(w http.ResponseWriter, name string, v pageView) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if w.Header().Get("Cache-Control") == "" {
		w.Header().Set("Cache-Control", "public, max-age=300")
	}
	_ = s.tmpl.ExecuteTemplate(w, name+".html", v)
}
