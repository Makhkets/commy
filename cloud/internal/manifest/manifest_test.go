package manifest

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
)

type vector struct {
	SeedHex   string `json:"seed_hex"`
	PublicKey string `json:"public_key"`
	NextKey   string `json:"next_key"`
	Compact   string `json:"compact"`
	Tampered  string `json:"tampered"`
}

func loadVector(t *testing.T) vector {
	t.Helper()
	raw, err := os.ReadFile("testdata/vector.json")
	if err != nil {
		t.Fatal(err)
	}
	var v vector
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

// The client (packages/commy_data/test/recovery) checks the same string with
// the Dart `cryptography` package: agreeing on it is what proves a manifest
// signed here opens on the phone.
func TestSharedVector(t *testing.T) {
	v := loadVector(t)
	s, err := Parse(v.Compact)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Verify(); err != nil {
		t.Fatalf("vector does not verify: %v", err)
	}
	if s.Manifest.ID != "axm" || s.Manifest.Seq != 3 || s.Manifest.Key != v.PublicKey || s.Manifest.NextKey != v.NextKey {
		t.Fatalf("unexpected manifest %+v", s.Manifest)
	}
	tampered, err := Parse(v.Tampered)
	if err != nil {
		t.Fatal(err)
	}
	if err := tampered.Verify(); !errors.Is(err, ErrSignature) {
		t.Fatalf("tampered vector verified: %v", err)
	}
}

func TestSignRoundTrip(t *testing.T) {
	seed := sha256.Sum256([]byte("round trip"))
	priv := ed25519.NewKeyFromSeed(seed[:])
	compact, err := Sign(Manifest{
		ID: "proj", Seq: 1, IssuedAt: 1791160000,
		Origin:     "HTTPS://Sub.Example.com:443",
		Mirrors:    []string{"https://m.example", "https://m.example"},
		Rendezvous: []string{"https://commy.example.net/r/proj"},
		Name:       "  Name  ",
	}, priv)
	if err != nil {
		t.Fatal(err)
	}
	s, err := Parse(compact)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
	m := s.Manifest
	if m.Origin != "https://sub.example.com" || len(m.Mirrors) != 1 || m.Name != "Name" {
		t.Fatalf("not normalised: %+v", m)
	}
}

func TestRefusals(t *testing.T) {
	seed := sha256.Sum256([]byte("refusals"))
	priv := ed25519.NewKeyFromSeed(seed[:])
	base := func() Manifest {
		return Manifest{ID: "p", Seq: 1, IssuedAt: 1, Origin: "https://a.example"}
	}
	cases := map[string]func(m *Manifest){
		"id with slash":        func(m *Manifest) { m.ID = "a/b" },
		"zero seq":             func(m *Manifest) { m.Seq = 0 },
		"origin with path":     func(m *Manifest) { m.Origin = "https://a.example/sub" },
		"origin with query":    func(m *Manifest) { m.Origin = "https://a.example?x=1" },
		"origin with user":     func(m *Manifest) { m.Origin = "https://u:p@a.example" },
		"ftp origin":           func(m *Manifest) { m.Origin = "ftp://a.example" },
		"mirror with path":     func(m *Manifest) { m.Mirrors = []string{"https://m.example/x"} },
		"http meeting point":   func(m *Manifest) { m.Rendezvous = []string{"http://r.example/x"} },
		"too many mirrors":     func(m *Manifest) { m.Mirrors = strings.Split(strings.Repeat("https://m.example,", 9), ",")[:9] },
		"blank name":           func(m *Manifest) { m.Name = "   " },
		"name too long":        func(m *Manifest) { m.Name = strings.Repeat("n", 65) },
		"bad next key":         func(m *Manifest) { m.NextKey = "AAAA" },
		"meeting point w/frag": func(m *Manifest) { m.Rendezvous = []string{"https://r.example/x#f"} },
	}
	for name, mutate := range cases {
		m := base()
		mutate(&m)
		if _, err := Sign(m, priv); !errors.Is(err, ErrFormat) {
			t.Errorf("%s: want ErrFormat, got %v", name, err)
		}
	}
	for name, compact := range map[string]string{
		"empty":      "",
		"two parts":  "v1.abc",
		"v2":         "v2.e30." + strings.Repeat("A", 86),
		"short sig":  "v1.e30.AAAA",
		"not json":   "v1." + Encode([]byte("nope")) + "." + Encode(make([]byte, 64)),
		"too long":   "v1." + strings.Repeat("A", 5000) + "." + strings.Repeat("A", 86),
		"empty json": "v1." + Encode([]byte("{}")) + "." + Encode(make([]byte, 64)),
		"json array": "v1." + Encode([]byte("[]")) + "." + Encode(make([]byte, 64)),
	} {
		if _, err := Parse(compact); err == nil {
			t.Errorf("%s: parsed", name)
		}
	}
}

func TestOrigin(t *testing.T) {
	for in, want := range map[string]string{
		"https://Sub.Example.com":      "https://sub.example.com",
		"https://sub.example.com/":     "https://sub.example.com",
		"https://sub.example.com:8443": "https://sub.example.com:8443",
		"http://a.example:80":          "http://a.example",
	} {
		got, err := Origin(in)
		if err != nil || got != want {
			t.Errorf("Origin(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
}
