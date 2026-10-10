// Package store keeps Commy Cloud's state in one JSON file.
//
// The service is small by design — operators, their projects, the manifests
// they publish, daily counters — and a file written atomically (temp file,
// fsync, rename) under one mutex is all it needs: no database server to run
// beside the owner's panel, nothing to migrate, and a backup is a copy of one
// file. Reads are served from memory.
//
// What is deliberately not here (docs/adr/0019-subscription-domain-
// recovery.md, "Что Commy Cloud видит"): operators' private keys, clients'
// IP addresses, subscription tokens, HWIDs.
package store

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// User is an operator account.
type User struct {
	ID       string    `json:"id"`
	Email    string    `json:"email"`
	PassHash string    `json:"pass_hash"`
	Admin    bool      `json:"admin,omitempty"`
	Disabled bool      `json:"disabled,omitempty"`
	Created  time.Time `json:"created"`
	Lang     string    `json:"lang,omitempty"`
}

// Session is a signed-in browser. Only the token's hash is kept.
type Session struct {
	Hash    string    `json:"hash"`
	UserID  string    `json:"user_id"`
	CSRF    string    `json:"csrf"`
	Expires time.Time `json:"expires"`
}

// Page is the white-label subscription page of a project.
type Page struct {
	Title   string   `json:"title,omitempty"`
	Accent  string   `json:"accent,omitempty"`
	Support string   `json:"support,omitempty"`
	Note    string   `json:"note,omitempty"`
	Apps    []string `json:"apps,omitempty"`
}

// Project is one operator brand: the manifest id, its key, its page.
type Project struct {
	ID       string    `json:"id"`
	OwnerID  string    `json:"owner_id"`
	Name     string    `json:"name"`
	Key      string    `json:"key"`
	NextKey  string    `json:"next_key,omitempty"`
	Created  time.Time `json:"created"`
	Disabled bool      `json:"disabled,omitempty"`
	Page     Page      `json:"page"`
}

// Release is one published manifest.
type Release struct {
	Seq       int64     `json:"seq"`
	Compact   string    `json:"compact"`
	Origin    string    `json:"origin"`
	Mirrors   []string  `json:"mirrors"`
	Published time.Time `json:"published"`
	By        string    `json:"by"`
}

// Token is an API token of a project. Only its hash is kept.
type Token struct {
	ID        string    `json:"id"`
	ProjectID string    `json:"project_id"`
	Name      string    `json:"name"`
	Hash      string    `json:"hash"`
	Created   time.Time `json:"created"`
	LastUsed  time.Time `json:"last_used,omitempty"`
}

// Event is one line of a project's audit log.
type Event struct {
	At     time.Time `json:"at"`
	By     string    `json:"by"`
	Action string    `json:"action"`
	Detail string    `json:"detail,omitempty"`
}

// Day is a project's meeting-point counters for one UTC day.
type Day struct {
	Visits   int            `json:"visits"`
	Unique   int            `json:"unique"`
	Versions map[string]int `json:"versions,omitempty"`
}

// Health is the last check of one origin or mirror.
type Health struct {
	URL     string    `json:"url"`
	Up      bool      `json:"up"`
	Status  int       `json:"status,omitempty"`
	Latency int64     `json:"latency_ms,omitempty"`
	Error   string    `json:"error,omitempty"`
	Checked time.Time `json:"checked"`
}

type data struct {
	Users    map[string]*User              `json:"users"`
	Sessions map[string]*Session           `json:"sessions"`
	Projects map[string]*Project           `json:"projects"`
	Releases map[string][]Release          `json:"releases"`
	Tokens   map[string]*Token             `json:"tokens"`
	Events   map[string][]Event            `json:"events"`
	Stats    map[string]map[string]*Day    `json:"stats"`
	Health   map[string]map[string]*Health `json:"health"`
}

// Store is the whole state, in memory, saved to path on every change.
type Store struct {
	mu   sync.RWMutex
	path string
	d    data
	// unique holds today's hashed visitors per project; never saved.
	unique    map[string]map[string]struct{}
	uniqueDay string
	salt      []byte
	now       func() time.Time
}

// Errors the web layer turns into answers.
var (
	ErrNotFound = errors.New("not found")
	ErrExists   = errors.New("already exists")
	ErrStale    = errors.New("not newer than the published release")
)

// MaxEvents is how many audit lines a project keeps.
const MaxEvents = 500

// Open loads path, or starts empty when it does not exist.
func Open(path string) (*Store, error) {
	s := &Store{path: path, now: time.Now, unique: map[string]map[string]struct{}{}}
	s.d = data{}
	raw, err := os.ReadFile(path)
	switch {
	case errors.Is(err, os.ErrNotExist):
	case err != nil:
		return nil, err
	default:
		if err := json.Unmarshal(raw, &s.d); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
	}
	s.init()
	return s, nil
}

// SetClock replaces the clock, for tests.
func (s *Store) SetClock(now func() time.Time) { s.now = now }

func (s *Store) init() {
	if s.d.Users == nil {
		s.d.Users = map[string]*User{}
	}
	if s.d.Sessions == nil {
		s.d.Sessions = map[string]*Session{}
	}
	if s.d.Projects == nil {
		s.d.Projects = map[string]*Project{}
	}
	if s.d.Releases == nil {
		s.d.Releases = map[string][]Release{}
	}
	if s.d.Tokens == nil {
		s.d.Tokens = map[string]*Token{}
	}
	if s.d.Events == nil {
		s.d.Events = map[string][]Event{}
	}
	if s.d.Stats == nil {
		s.d.Stats = map[string]map[string]*Day{}
	}
	if s.d.Health == nil {
		s.d.Health = map[string]map[string]*Health{}
	}
}

// save writes the state atomically. Called with mu held.
func (s *Store) save() error {
	if s.path == "" {
		return nil
	}
	raw, err := json.MarshalIndent(s.d, "", " ")
	if err != nil {
		return err
	}
	dir := filepath.Dir(s.path)
	tmp, err := os.CreateTemp(dir, ".cloud-*.json")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.Write(raw); err != nil {
		tmp.Close()
		os.Remove(name)
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return err
	}
	if err := os.Chmod(name, 0o600); err != nil {
		os.Remove(name)
		return err
	}
	return os.Rename(name, s.path)
}

// NewID returns n random bytes as hex.
func NewID(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// Hash is the SHA-256 of a secret token, as stored.
func Hash(secret string) string {
	sum := sha256.Sum256([]byte(secret))
	return hex.EncodeToString(sum[:])
}

// ---- users ----

// AddUser stores a new operator; the first one ever is the admin.
func (s *Store) AddUser(email, passHash string) (*User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, u := range s.d.Users {
		if u.Email == email {
			return nil, ErrExists
		}
	}
	u := &User{ID: NewID(8), Email: email, PassHash: passHash, Created: s.now().UTC()}
	if len(s.d.Users) == 0 {
		u.Admin = true
	}
	s.d.Users[u.ID] = u
	return copyUser(u), s.save()
}

// UserByEmail finds an operator by e-mail.
func (s *Store) UserByEmail(email string) (*User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, u := range s.d.Users {
		if u.Email == email {
			return copyUser(u), nil
		}
	}
	return nil, ErrNotFound
}

// User finds an operator by id.
func (s *Store) User(id string) (*User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	u, ok := s.d.Users[id]
	if !ok {
		return nil, ErrNotFound
	}
	return copyUser(u), nil
}

// Users lists every operator, oldest first.
func (s *Store) Users() []User {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]User, 0, len(s.d.Users))
	for _, u := range s.d.Users {
		out = append(out, *u)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Created.Before(out[j].Created) })
	return out
}

// UpdateUser applies change to the stored operator.
func (s *Store) UpdateUser(id string, change func(*User)) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.d.Users[id]
	if !ok {
		return ErrNotFound
	}
	change(u)
	return s.save()
}

func copyUser(u *User) *User { c := *u; return &c }

// ---- sessions ----

// AddSession signs a user in; returns the token for the cookie.
func (s *Store) AddSession(userID string, ttl time.Duration) (token string, sess Session, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now().UTC()
	for hash, existing := range s.d.Sessions {
		if existing.Expires.Before(now) {
			delete(s.d.Sessions, hash)
		}
	}
	token = NewID(32)
	sess = Session{Hash: Hash(token), UserID: userID, CSRF: NewID(16), Expires: now.Add(ttl)}
	s.d.Sessions[sess.Hash] = &sess
	return token, sess, s.save()
}

// Session finds a live session by its token.
func (s *Store) Session(token string) (*Session, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	sess, ok := s.d.Sessions[Hash(token)]
	if !ok || sess.Expires.Before(s.now()) {
		return nil, ErrNotFound
	}
	c := *sess
	return &c, nil
}

// DropSession signs a browser out.
func (s *Store) DropSession(token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.d.Sessions, Hash(token))
	return s.save()
}

// ---- projects ----

// AddProject creates a project with its first public key.
func (s *Store) AddProject(p Project, by string) (*Project, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.d.Projects[p.ID]; ok {
		return nil, ErrExists
	}
	p.Created = s.now().UTC()
	s.d.Projects[p.ID] = &p
	s.event(p.ID, by, "project.created", p.Name)
	c := p
	return &c, s.save()
}

// Project finds a project by id.
func (s *Store) Project(id string) (*Project, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.d.Projects[id]
	if !ok {
		return nil, ErrNotFound
	}
	c := *p
	return &c, nil
}

// Projects lists the projects of ownerID ("" for all), newest first.
func (s *Store) Projects(ownerID string) []Project {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []Project{}
	for _, p := range s.d.Projects {
		if ownerID == "" || p.OwnerID == ownerID {
			out = append(out, *p)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Created.After(out[j].Created) })
	return out
}

// UpdateProject applies change and records action in the audit log.
func (s *Store) UpdateProject(id, by, action, detail string, change func(*Project)) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.d.Projects[id]
	if !ok {
		return ErrNotFound
	}
	change(p)
	s.event(id, by, action, detail)
	return s.save()
}

// DeleteProject removes a project and everything that belongs to it.
func (s *Store) DeleteProject(id, by string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.d.Projects[id]; !ok {
		return ErrNotFound
	}
	delete(s.d.Projects, id)
	delete(s.d.Releases, id)
	delete(s.d.Events, id)
	delete(s.d.Stats, id)
	delete(s.d.Health, id)
	for tid, t := range s.d.Tokens {
		if t.ProjectID == id {
			delete(s.d.Tokens, tid)
		}
	}
	return s.save()
}

// ---- releases ----

// Publish stores a verified release. Its seq must exceed the last one.
// rotate moves the project's key along an announced rotation.
func (s *Store) Publish(projectID string, r Release, key, nextKey string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.d.Projects[projectID]
	if !ok {
		return ErrNotFound
	}
	list := s.d.Releases[projectID]
	if len(list) > 0 && r.Seq <= list[len(list)-1].Seq {
		return ErrStale
	}
	r.Published = s.now().UTC()
	s.d.Releases[projectID] = append(list, r)
	p.Key = key
	p.NextKey = nextKey
	s.event(projectID, r.By, "manifest.published", fmt.Sprintf("#%d %s", r.Seq, r.Origin))
	return s.save()
}

// Latest is the newest release of a project.
func (s *Store) Latest(projectID string) (*Release, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := s.d.Releases[projectID]
	if len(list) == 0 {
		return nil, ErrNotFound
	}
	r := list[len(list)-1]
	return &r, nil
}

// Releases lists a project's releases, newest first.
func (s *Store) Releases(projectID string) []Release {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := s.d.Releases[projectID]
	out := make([]Release, len(list))
	for i := range list {
		out[len(list)-1-i] = list[i]
	}
	return out
}

// ---- tokens ----

// AddToken creates an API token; the secret is returned once.
func (s *Store) AddToken(projectID, name, by string) (secret string, t Token, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.d.Projects[projectID]; !ok {
		return "", Token{}, ErrNotFound
	}
	secret = "cct_" + NewID(24)
	t = Token{ID: NewID(6), ProjectID: projectID, Name: name, Hash: Hash(secret), Created: s.now().UTC()}
	s.d.Tokens[t.ID] = &t
	s.event(projectID, by, "token.created", name)
	return secret, t, s.save()
}

// TokenBySecret finds the token a request carries and stamps its use.
func (s *Store) TokenBySecret(secret string) (*Token, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	hash := Hash(secret)
	for _, t := range s.d.Tokens {
		if t.Hash == hash {
			t.LastUsed = s.now().UTC()
			c := *t
			return &c, nil
		}
	}
	return nil, ErrNotFound
}

// Tokens lists a project's tokens.
func (s *Store) Tokens(projectID string) []Token {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []Token{}
	for _, t := range s.d.Tokens {
		if t.ProjectID == projectID {
			out = append(out, *t)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Created.Before(out[j].Created) })
	return out
}

// DropToken revokes a token.
func (s *Store) DropToken(projectID, tokenID, by string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.d.Tokens[tokenID]
	if !ok || t.ProjectID != projectID {
		return ErrNotFound
	}
	delete(s.d.Tokens, tokenID)
	s.event(projectID, by, "token.revoked", t.Name)
	return s.save()
}

// ---- audit ----

func (s *Store) event(projectID, by, action, detail string) {
	list := append(s.d.Events[projectID], Event{At: s.now().UTC(), By: by, Action: action, Detail: detail})
	if len(list) > MaxEvents {
		list = list[len(list)-MaxEvents:]
	}
	s.d.Events[projectID] = list
}

// Events lists a project's audit log, newest first.
func (s *Store) Events(projectID string) []Event {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := s.d.Events[projectID]
	out := make([]Event, len(list))
	for i := range list {
		out[len(list)-1-i] = list[i]
	}
	return out
}

// ---- stats ----

// CountVisit records one meeting-point visit. visitor is hashed with a salt
// that changes every day and is never stored, so a visitor can be counted
// once a day and never recognised again.
func (s *Store) CountVisit(projectID, visitor, version string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	day := s.now().UTC().Format("2006-01-02")
	if s.uniqueDay != day {
		s.uniqueDay = day
		s.unique = map[string]map[string]struct{}{}
		s.salt = []byte(NewID(16))
	}
	days := s.d.Stats[projectID]
	if days == nil {
		days = map[string]*Day{}
		s.d.Stats[projectID] = days
	}
	d := days[day]
	if d == nil {
		d = &Day{Versions: map[string]int{}}
		days[day] = d
	}
	d.Visits++
	if version != "" {
		if d.Versions == nil {
			d.Versions = map[string]int{}
		}
		if len(d.Versions) < 50 || d.Versions[version] > 0 {
			d.Versions[version]++
		}
	}
	sum := sha256.Sum256(append(append([]byte{}, s.salt...), visitor...))
	key := hex.EncodeToString(sum[:8])
	seen := s.unique[projectID]
	if seen == nil {
		seen = map[string]struct{}{}
		s.unique[projectID] = seen
	}
	if _, ok := seen[key]; !ok {
		seen[key] = struct{}{}
		d.Unique++
	}
}

// Flush saves counters; the web layer calls it on a timer, not per visit.
func (s *Store) Flush() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.save()
}

// DayStat is one day of a project's counters.
type DayStat struct {
	Date string
	Day
}

// MaxStatDays is the most days Stats returns: a year. The API asks for a
// number the caller chose, and the slice is sized by it.
const MaxStatDays = 365

// Stats returns the last n days of a project's counters, oldest first,
// including days with nothing. n is clamped to 0..MaxStatDays.
func (s *Store) Stats(projectID string, n int) []DayStat {
	n = min(max(n, 0), MaxStatDays)
	s.mu.RLock()
	defer s.mu.RUnlock()
	now := s.now().UTC()
	// Grown by append rather than sized up front by a number from a request.
	out := []DayStat{}
	for i := n - 1; i >= 0; i-- {
		day := now.AddDate(0, 0, -i).Format("2006-01-02")
		stat := DayStat{Date: day}
		if d := s.d.Stats[projectID][day]; d != nil {
			stat.Day = *d
			stat.Day.Versions = copyCounts(d.Versions)
		}
		out = append(out, stat)
	}
	return out
}

func copyCounts(m map[string]int) map[string]int {
	out := make(map[string]int, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// ---- health ----

// SetHealth records the last check of url for a project.
func (s *Store) SetHealth(projectID string, h Health) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m := s.d.Health[projectID]
	if m == nil {
		m = map[string]*Health{}
		s.d.Health[projectID] = m
	}
	m[h.URL] = &h
}

// HealthOf returns the last checks for a project, by URL.
func (s *Store) HealthOf(projectID string) map[string]Health {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := map[string]Health{}
	for k, v := range s.d.Health[projectID] {
		out[k] = *v
	}
	return out
}
