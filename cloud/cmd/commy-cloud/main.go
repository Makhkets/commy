// Command commy-cloud is Commy Cloud: the meeting points and dashboard of
// docs/adr/0019-subscription-domain-recovery.md, and the operator's offline
// tools for the same protocol.
//
//	commy-cloud serve                      run the service (env below)
//	commy-cloud keygen -project ID -o FILE make a key file
//	commy-cloud sign -key FILE -seq N -origin URL [-mirror URL]... [-rendezvous URL]... [-name NAME] [-next-key KEY]
//	commy-cloud verify MANIFEST            check a manifest's shape and signature
//
// Environment of `serve`:
//
//	COMMY_CLOUD_ADDR         listen address (":8080")
//	COMMY_CLOUD_DATA         state file ("data/cloud.json")
//	COMMY_CLOUD_BASE_URL     public address ("http://localhost:8080")
//	COMMY_CLOUD_OPEN_SIGNUP  "1": anyone may register (the first account always may)
//	COMMY_CLOUD_TRUST_PROXY  "1": client address from X-Forwarded-For (behind Caddy)
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/Makhkets/commy/cloud/internal/manifest"
	"github.com/Makhkets/commy/cloud/internal/site"
	"github.com/Makhkets/commy/cloud/internal/store"
	"github.com/Makhkets/commy/cloud/internal/web"
)

func main() {
	if len(os.Args) < 2 {
		os.Args = append(os.Args, "serve")
	}
	var err error
	switch os.Args[1] {
	case "serve":
		err = serve()
	case "keygen":
		err = keygen(os.Args[2:])
	case "sign":
		err = sign(os.Args[2:])
	case "verify":
		err = verify(os.Args[2:])
	default:
		err = fmt.Errorf("unknown command %q (serve, keygen, sign, verify)", os.Args[1])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "commy-cloud:", err)
		os.Exit(1)
	}
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

func serve() error {
	log := slog.New(slog.NewTextHandler(os.Stdout, nil))
	dataPath := env("COMMY_CLOUD_DATA", "data/cloud.json")
	if err := os.MkdirAll(filepath.Dir(dataPath), 0o700); err != nil {
		return err
	}
	st, err := store.Open(dataPath)
	if err != nil {
		return err
	}
	base := env("COMMY_CLOUD_BASE_URL", "http://localhost:8080")
	docs, err := site.New(base)
	if err != nil {
		return err
	}
	srv, err := web.New(web.Config{
		BaseURL:    base,
		OpenSignup: os.Getenv("COMMY_CLOUD_OPEN_SIGNUP") == "1",
		TrustProxy: os.Getenv("COMMY_CLOUD_TRUST_PROXY") == "1",
		Site:       docs,
		Logger:     log,
	}, st)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go srv.RunHealth(ctx, 10*time.Minute)
	httpServer := &http.Server{
		Addr:              env("COMMY_CLOUD_ADDR", ":8080"),
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(shutdown)
	}()
	log.Info("listening", "addr", httpServer.Addr, "base", base, "data", dataPath)
	err = httpServer.ListenAndServe()
	_ = st.Flush()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

// keyFile is the same JSON the dashboard downloads.
type keyFile struct {
	V          int    `json:"v"`
	Type       string `json:"type"`
	Project    string `json:"project"`
	PublicKey  string `json:"public_key"`
	PrivateKey string `json:"private_key"`
	Created    string `json:"created"`
	Note       string `json:"note"`
}

func keygen(args []string) error {
	fs := flag.NewFlagSet("keygen", flag.ExitOnError)
	project := fs.String("project", "", "project identifier")
	out := fs.String("o", "", "file to write (refuses to overwrite)")
	_ = fs.Parse(args)
	if !manifest.ValidID(*project) || *out == "" {
		return errors.New("usage: keygen -project ID -o FILE")
	}
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		return err
	}
	pkcs8, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return err
	}
	raw, _ := json.MarshalIndent(keyFile{
		V: 1, Type: "commy-recovery-key", Project: *project,
		PublicKey: manifest.Encode(pub), PrivateKey: manifest.Encode(pkcs8),
		Created: time.Now().UTC().Format(time.RFC3339),
		Note:    "Keep this file safe and offline. Without it you cannot move your clients to a new address.",
	}, "", "  ")
	f, err := os.OpenFile(*out, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.Write(append(raw, '\n')); err != nil {
		return err
	}
	fmt.Println(manifest.Encode(pub))
	return nil
}

type multi []string

func (m *multi) String() string     { return strings.Join(*m, ",") }
func (m *multi) Set(v string) error { *m = append(*m, v); return nil }

func sign(args []string) error {
	fs := flag.NewFlagSet("sign", flag.ExitOnError)
	keyPath := fs.String("key", "", "key file")
	project := fs.String("project", "", "project identifier (default: the key file's)")
	seq := fs.Int64("seq", 0, "release number, greater than the published one")
	origin := fs.String("origin", "", "main address, https://host[:port]")
	name := fs.String("name", "", "name shown to users")
	nextKey := fs.String("next-key", "", "next key, to announce a rotation")
	var mirrors, points multi
	fs.Var(&mirrors, "mirror", "spare address (repeat)")
	fs.Var(&points, "rendezvous", "meeting point URL (repeat)")
	_ = fs.Parse(args)
	raw, err := os.ReadFile(*keyPath)
	if err != nil {
		return err
	}
	var kf keyFile
	if err := json.Unmarshal(raw, &kf); err != nil || kf.Type != "commy-recovery-key" {
		return errors.New("not a commy key file")
	}
	der, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(kf.PrivateKey, "="))
	if err != nil {
		return err
	}
	parsed, err := x509.ParsePKCS8PrivateKey(der)
	if err != nil {
		return err
	}
	priv, ok := parsed.(ed25519.PrivateKey)
	if !ok {
		return errors.New("the key file does not hold an Ed25519 key")
	}
	id := *project
	if id == "" {
		id = kf.Project
	}
	compact, err := manifest.Sign(manifest.Manifest{
		ID: id, Seq: *seq, IssuedAt: time.Now().Unix(), Origin: *origin,
		Mirrors: mirrors, Rendezvous: points, Name: *name, NextKey: *nextKey,
	}, priv)
	if err != nil {
		return err
	}
	fmt.Println(compact)
	return nil
}

func verify(args []string) error {
	if len(args) != 1 {
		return errors.New("usage: verify MANIFEST")
	}
	signed, err := manifest.Parse(args[0])
	if err != nil {
		return err
	}
	if err := signed.Verify(); err != nil {
		return err
	}
	out, _ := json.MarshalIndent(signed.Manifest, "", "  ")
	fmt.Println(string(out))
	return nil
}
