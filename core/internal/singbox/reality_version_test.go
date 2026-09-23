//go:build commy_overlay

package singbox_test

import (
	"bufio"
	"context"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"io"
	"math/big"
	"net"
	"testing"
	"time"

	utls "github.com/metacubex/utls"
	sbtls "github.com/sagernet/sing-box/common/tls"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/logger"
)

// This test needs the build overlay, because the version is written by
// sing-box itself:
//
//	GODEBUG=goindex=0 go test -overlay="$(go run ./cmd/overlaygen)" \
//	    -tags "<core tags>,commy_overlay" ./internal/singbox/
//
// Xray 26.7.28 refuses REALITY clients older than 26.3.27 unless the server's
// owner set a range of their own, and sing-box introduces itself as 1.8.1. A
// refused client is shown the cover site's certificate instead of REALITY's,
// which is how every node of a panel on that release answered this app.
//
// The server here is the REALITY server sing-box's own library carries, with
// the floor Xray applies by default; the cover site is a local TLS server.
func TestRealityClientClearsXraysDefaultVersionFloor(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	const serverName = "cover.test"
	cover := startCoverSite(t, serverName)

	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	shortID := [8]byte{0xa1, 0xb2, 0xc4, 0xd4, 0xa1, 0xb2, 0xc5, 0xd5}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })

	serverConfig := &utls.RealityConfig{
		DialContext: new(net.Dialer).DialContext,
		Type:        "tcp",
		Dest:        cover,
		ServerNames: map[string]bool{serverName: true},
		PrivateKey:  key.Bytes(),
		// What Xray 26.7.28 applies when the server's owner sets no range.
		MinClientVer: []byte{26, 3, 27},
		ShortIds:     map[[8]byte]bool{shortID: true},
	}
	serverConfig.SessionTicketsDisabled = true
	go serveEcho(ctx, listener, serverConfig)

	clientConfig, err := sbtls.NewRealityClient(ctx, logger.NOP(), serverName, option.OutboundTLSOptions{
		Enabled:    true,
		ServerName: serverName,
		UTLS:       &option.OutboundUTLSOptions{Enabled: true, Fingerprint: "chrome"},
		Reality: &option.OutboundRealityOptions{
			Enabled:   true,
			PublicKey: base64.RawURLEncoding.EncodeToString(key.PublicKey().Bytes()),
			ShortID:   "a1b2c4d4a1b2c5d5",
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	raw, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	conn, err := sbtls.ClientHandshake(ctx, raw, clientConfig)
	if err != nil {
		t.Fatalf("a REALITY server with Xray's default version floor refused the client: %v", err)
	}
	defer conn.Close()

	// Past the handshake the server is REALITY's, not the cover site's: it
	// answers what it was sent.
	if _, err := conn.Write([]byte("ping\n")); err != nil {
		t.Fatal(err)
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	if line != "ping\n" {
		t.Fatalf("echo read %q", line)
	}
}

// startCoverSite runs the site a REALITY server borrows its handshake from:
// TLS 1.3 with a certificate the client has no reason to trust.
func startCoverSite(t *testing.T, serverName string) string {
	t.Helper()
	private, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: serverName},
		DNSNames:     []string{serverName},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &private.PublicKey, private)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{
		Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: private}},
		MinVersion:   tls.VersionTLS13,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				_, _ = io.Copy(io.Discard, conn)
			}()
		}
	}()
	return listener.Addr().String()
}

// serveEcho accepts one connection, runs REALITY on it and echoes a line.
func serveEcho(ctx context.Context, listener net.Listener, config *utls.RealityConfig) {
	conn, err := listener.Accept()
	if err != nil {
		return
	}
	defer conn.Close()
	server, err := utls.RealityServer(ctx, conn, config)
	if err != nil {
		return
	}
	line, err := bufio.NewReader(server).ReadString('\n')
	if err != nil {
		return
	}
	_, _ = server.Write([]byte(line))
}
