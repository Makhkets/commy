// Package manifest is the wire format of a subscription provider's signed
// recovery manifest — docs/adr/0019-subscription-domain-recovery.md.
//
// The same rules as the client's `SignedManifest.parse` (commy_domain), in
// Go: the server refuses at publish time anything a phone would refuse at
// read time, so an operator learns of a mistake in the dashboard and not
// from users who stopped getting updates. Both sides are held to one vector
// signed by crypto/ed25519 (testdata/vector.json).
package manifest

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"
)

// Format limits, identical to the client's.
const (
	Version       = 1
	MaxLength     = 4096
	MaxMirrors    = 8
	MaxRendezvous = 4
	MaxName       = 64
)

// Manifest is the signed statement, as the client reads it.
type Manifest struct {
	V          int      `json:"v"`
	ID         string   `json:"id"`
	Seq        int64    `json:"seq"`
	IssuedAt   int64    `json:"iat"`
	Origin     string   `json:"origin"`
	Mirrors    []string `json:"mirrors"`
	Rendezvous []string `json:"rendezvous"`
	Key        string   `json:"key"`
	NextKey    string   `json:"next_key,omitempty"`
	Name       string   `json:"name,omitempty"`
}

// Issued is IssuedAt as a time.
func (m Manifest) Issued() time.Time { return time.Unix(m.IssuedAt, 0).UTC() }

// Signed is a parsed compact manifest: what it says, and what was signed.
type Signed struct {
	Manifest  Manifest
	Compact   string
	signed    []byte
	signature []byte
	publicKey ed25519.PublicKey
}

var (
	idPattern  = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)
	b64Pattern = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

	// ErrFormat is returned for anything that is not a well-formed manifest.
	ErrFormat = errors.New("not a well-formed manifest")
	// ErrSignature is returned when the signature does not hold.
	ErrSignature = errors.New("the signature does not hold")
)

// ValidID reports whether id can name a project.
func ValidID(id string) bool { return idPattern.MatchString(id) }

// Parse reads compact (`v1.<payload>.<signature>`), checking its shape and
// every limit, but not the signature — Verify does that.
func Parse(compact string) (*Signed, error) {
	text := strings.TrimSpace(compact)
	if text == "" || len(text) > MaxLength {
		return nil, fmt.Errorf("%w: length", ErrFormat)
	}
	parts := strings.Split(text, ".")
	if len(parts) != 3 || parts[0] != "v1" {
		return nil, fmt.Errorf("%w: not v1.<payload>.<signature>", ErrFormat)
	}
	payload, err := decode(parts[1])
	if err != nil {
		return nil, fmt.Errorf("%w: payload", ErrFormat)
	}
	signature, err := decode(parts[2])
	if err != nil || len(signature) != ed25519.SignatureSize {
		return nil, fmt.Errorf("%w: signature", ErrFormat)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, fmt.Errorf("%w: payload is not a JSON object", ErrFormat)
	}
	var m Manifest
	if err := json.Unmarshal(payload, &m); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrFormat, err)
	}
	if err := m.Check(); err != nil {
		return nil, err
	}
	key, _ := decode(m.Key)
	return &Signed{
		Manifest:  m,
		Compact:   text,
		signed:    []byte(parts[0] + "." + parts[1]),
		signature: signature,
		publicKey: ed25519.PublicKey(key),
	}, nil
}

// Check applies every rule of the format to m.
func (m *Manifest) Check() error {
	switch {
	case m.V != Version:
		return fmt.Errorf("%w: version", ErrFormat)
	case !ValidID(m.ID):
		return fmt.Errorf("%w: id", ErrFormat)
	case m.Seq < 1:
		return fmt.Errorf("%w: seq", ErrFormat)
	case m.IssuedAt < 0:
		return fmt.Errorf("%w: iat", ErrFormat)
	}
	origin, err := Origin(m.Origin)
	if err != nil {
		return fmt.Errorf("%w: origin: %v", ErrFormat, err)
	}
	m.Origin = origin
	if len(m.Mirrors) > MaxMirrors {
		return fmt.Errorf("%w: too many mirrors", ErrFormat)
	}
	mirrors := make([]string, 0, len(m.Mirrors))
	for _, raw := range m.Mirrors {
		mirror, err := Origin(raw)
		if err != nil {
			return fmt.Errorf("%w: mirror: %v", ErrFormat, err)
		}
		mirrors = appendUnique(mirrors, mirror)
	}
	m.Mirrors = mirrors
	if len(m.Rendezvous) > MaxRendezvous {
		return fmt.Errorf("%w: too many meeting points", ErrFormat)
	}
	points := make([]string, 0, len(m.Rendezvous))
	for _, raw := range m.Rendezvous {
		if err := Rendezvous(raw); err != nil {
			return fmt.Errorf("%w: meeting point: %v", ErrFormat, err)
		}
		points = appendUnique(points, raw)
	}
	m.Rendezvous = points
	if key, err := decode(m.Key); err != nil || len(key) != ed25519.PublicKeySize {
		return fmt.Errorf("%w: key", ErrFormat)
	}
	if m.NextKey != "" {
		if key, err := decode(m.NextKey); err != nil || len(key) != ed25519.PublicKeySize {
			return fmt.Errorf("%w: next_key", ErrFormat)
		}
	}
	if m.Name != "" && (strings.TrimSpace(m.Name) == "" || len([]rune(m.Name)) > MaxName) {
		return fmt.Errorf("%w: name", ErrFormat)
	}
	m.Name = strings.TrimSpace(m.Name)
	return nil
}

// Verify checks the signature against the key the manifest names.
func (s *Signed) Verify() error {
	if !ed25519.Verify(s.publicKey, s.signed, s.signature) {
		return ErrSignature
	}
	return nil
}

// Sign builds the compact form of m with priv. m.Key is set from priv.
func Sign(m Manifest, priv ed25519.PrivateKey) (string, error) {
	m.V = Version
	m.Key = Encode(priv.Public().(ed25519.PublicKey))
	if m.Mirrors == nil {
		m.Mirrors = []string{}
	}
	if m.Rendezvous == nil {
		m.Rendezvous = []string{}
	}
	if err := m.Check(); err != nil {
		return "", err
	}
	payload, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	signed := "v1." + Encode(payload)
	compact := signed + "." + Encode(ed25519.Sign(priv, []byte(signed)))
	if len(compact) > MaxLength {
		return "", fmt.Errorf("%w: longer than %d", ErrFormat, MaxLength)
	}
	return compact, nil
}

// Origin returns raw if it is exactly `http(s)://host[:port]`, lowercased.
// A path, query, fragment or user info is refused, not dropped: a manifest
// naming a path means its author expects it honoured.
func Origin(raw string) (string, error) {
	if len(raw) > 255 {
		return "", errors.New("too long")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme != "http" && scheme != "https" {
		return "", errors.New("not http(s)")
	}
	if u.Host == "" || u.Hostname() == "" {
		return "", errors.New("no host")
	}
	if u.User != nil || (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" || u.ForceQuery {
		return "", errors.New("only scheme, host and port")
	}
	host := strings.ToLower(u.Hostname())
	if port := u.Port(); port != "" && !(scheme == "https" && port == "443") && !(scheme == "http" && port == "80") {
		return scheme + "://" + joinHostPort(host, port), nil
	}
	return scheme + "://" + bracket(host), nil
}

// Rendezvous checks a meeting point: a full https URL without credentials
// or fragment.
func Rendezvous(raw string) error {
	if len(raw) > 512 {
		return errors.New("too long")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if strings.ToLower(u.Scheme) != "https" || u.Hostname() == "" {
		return errors.New("not https")
	}
	if u.User != nil || u.Fragment != "" {
		return errors.New("credentials or fragment")
	}
	return nil
}

// Encode is base64url without padding.
func Encode(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func decode(s string) ([]byte, error) {
	if s == "" || !b64Pattern.MatchString(s) || len(s)%4 == 1 {
		return nil, errors.New("not base64url")
	}
	return base64.RawURLEncoding.DecodeString(strings.TrimRight(s, "="))
}

func appendUnique(list []string, item string) []string {
	for _, existing := range list {
		if existing == item {
			return list
		}
	}
	return append(list, item)
}

func bracket(host string) string {
	if strings.Contains(host, ":") {
		return "[" + host + "]"
	}
	return host
}

func joinHostPort(host, port string) string { return bracket(host) + ":" + port }
