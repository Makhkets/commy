package xhttp

import (
	"io"
	"testing"

	"github.com/Makhkets/commy/core/xhttp/config"
	M "github.com/sagernet/sing/common/metadata"
)

// What the end-to-end test needs from the in-package test double. It lives in
// package xhttp_test because it imports sing-box, and sing-box — through the
// overlay — imports this package.

// FakeEndpoint is a running fake Xray server.
type FakeEndpoint struct {
	Addr M.Socksaddr
	e    *endpoint
}

// StartFakeXrayHTTP2 serves XHTTP over TLS with a self-signed certificate and
// hands every proxied connection to [serve].
func StartFakeXrayHTTP2(t testing.TB, options config.Options, serve func(io.ReadWriteCloser)) *FakeEndpoint {
	e := startHTTP2(t, options)
	e.server.serve = serve
	return &FakeEndpoint{Addr: e.addr, e: e}
}

// RequestCount reports how many HTTP requests the server has recorded.
func (f *FakeEndpoint) RequestCount() int { return len(f.e.server.recorded()) }
