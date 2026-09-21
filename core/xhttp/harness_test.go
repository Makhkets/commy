package xhttp

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	"github.com/sagernet/quic-go/http3"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	aTLS "github.com/sagernet/sing/common/tls"
)

// stdTLS is the smallest thing that satisfies sing's TLS configuration
// interface: the standard library, and nothing else. The transport is tested
// against the interface it is given, not against sing-box's uTLS stack.
type stdTLS struct{ config *tls.Config }

func (c *stdTLS) ServerName() string                  { return c.config.ServerName }
func (c *stdTLS) SetServerName(name string)           { c.config.ServerName = name }
func (c *stdTLS) NextProtos() []string                { return c.config.NextProtos }
func (c *stdTLS) SetNextProtos(protos []string)       { c.config.NextProtos = protos }
func (c *stdTLS) STDConfig() (*aTLS.STDConfig, error) { return c.config, nil }
func (c *stdTLS) Clone() aTLS.Config                  { return &stdTLS{c.config.Clone()} }
func (c *stdTLS) Client(conn net.Conn) (aTLS.Conn, error) {
	return tls.Client(conn, c.config), nil
}

func selfSigned(t testing.TB) tls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "xhttp.test"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		DNSNames:     []string{"xhttp.test"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}

// endpoint is a running fake server and what a client needs to reach it.
type endpoint struct {
	server   *fakeXray
	addr     M.Socksaddr
	tls      aTLS.Config
	listener *countingListener
}

// startHTTP1 serves XHTTP over cleartext HTTP/1.1.
func startHTTP1(t testing.TB, options config.Options) *endpoint {
	t.Helper()
	server := newFakeXray(t, options)
	listener := listenTCP(t)
	httpServer := httptest.NewUnstartedServer(server)
	httpServer.Listener = listener
	httpServer.Start()
	t.Cleanup(httpServer.Close)
	return &endpoint{server: server, addr: M.SocksaddrFromNet(listener.Addr()), listener: listener}
}

// startHTTP2 serves XHTTP over TLS with ALPN h2.
func startHTTP2(t testing.TB, options config.Options) *endpoint {
	t.Helper()
	server := newFakeXray(t, options)
	listener := listenTCP(t)
	httpServer := httptest.NewUnstartedServer(server)
	httpServer.Listener = listener
	httpServer.EnableHTTP2 = true
	httpServer.TLS = &tls.Config{Certificates: []tls.Certificate{selfSigned(t)}}
	httpServer.StartTLS()
	t.Cleanup(httpServer.Close)
	return &endpoint{
		server:   server,
		addr:     M.SocksaddrFromNet(listener.Addr()),
		tls:      &stdTLS{&tls.Config{InsecureSkipVerify: true, ServerName: "xhttp.test"}},
		listener: listener,
	}
}

// startHTTP3 serves XHTTP over QUIC.
func startHTTP3(t testing.TB, options config.Options) *endpoint {
	t.Helper()
	server := newFakeXray(t, options)
	packetConn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	h3 := &http3.Server{
		Handler:   server,
		TLSConfig: http3.ConfigureTLSConfig(&tls.Config{Certificates: []tls.Certificate{selfSigned(t)}}),
	}
	go func() { _ = h3.Serve(packetConn) }()
	t.Cleanup(func() {
		_ = h3.Close()
		_ = packetConn.Close()
	})
	return &endpoint{
		server: server,
		addr:   M.SocksaddrFromNet(packetConn.LocalAddr()),
		tls: &stdTLS{&tls.Config{
			InsecureSkipVerify: true,
			ServerName:         "xhttp.test",
			NextProtos:         []string{"h3"},
		}},
	}
}

func listenTCP(t testing.TB) *countingListener {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	return &countingListener{Listener: listener}
}

// dialClient builds a transport against [e] and closes it with the test.
func dialClient(t testing.TB, e *endpoint, options config.Options) *Client {
	t.Helper()
	transport, err := NewClient(context.Background(), N.SystemDialer, e.addr, options, e.tls)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	client := transport.(*Client)
	t.Cleanup(func() { _ = client.Close() })
	return client
}

var _ http.Handler = (*fakeXray)(nil)

func insecureTLS() *tls.Config {
	return &tls.Config{InsecureSkipVerify: true, ServerName: "xhttp.test"}
}
