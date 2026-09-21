package xhttp

import (
	"bytes"
	"context"
	"crypto/rand"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

func randomBytes(t testing.TB, n int) []byte {
	t.Helper()
	data := make([]byte, n)
	if _, err := rand.Read(data); err != nil {
		t.Fatal(err)
	}
	return data
}

// roundTrip writes [payload] and expects the echo server to return it intact.
func roundTrip(t testing.TB, conn net.Conn, payload []byte) {
	t.Helper()
	errs := make(chan error, 1)
	go func() {
		// Uneven pieces, as a real proxied connection writes them.
		for offset := 0; offset < len(payload); {
			size := min(1+offset%7919, len(payload)-offset)
			if _, err := conn.Write(payload[offset : offset+size]); err != nil {
				errs <- err
				return
			}
			offset += size
		}
		errs <- nil
	}()
	received := make([]byte, len(payload))
	if _, err := io.ReadFull(conn, received); err != nil {
		t.Fatalf("read echo: %v", err)
	}
	if err := <-errs; err != nil {
		t.Fatalf("write: %v", err)
	}
	if !bytes.Equal(received, payload) {
		t.Fatal("echo differs from what was sent")
	}
}

func dialOrFail(t testing.TB, client *Client) net.Conn {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx)
	if err != nil {
		t.Fatalf("DialContext: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn
}

func TestModesCarryDataOverEveryHTTPVersion(t *testing.T) {
	versions := []struct {
		name  string
		start func(testing.TB, config.Options) *endpoint
		proto int
	}{
		{"http1", startHTTP1, 1},
		{"http2", startHTTP2, 2},
		{"http3", startHTTP3, 3},
	}
	modes := []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne}
	for _, version := range versions {
		for _, mode := range modes {
			t.Run(version.name+"/"+mode, func(t *testing.T) {
				options := config.Options{Mode: mode, Path: "/tunnel"}
				e := version.start(t, options)
				conn := dialOrFail(t, dialClient(t, e, options))
				roundTrip(t, conn, randomBytes(t, 3<<20))

				for _, request := range e.server.recorded() {
					if request.proto != version.proto {
						t.Fatalf("request went over HTTP/%d, want HTTP/%d", request.proto, version.proto)
					}
				}
			})
		}
	}
}

func TestAutoWithoutRealityIsPacketUp(t *testing.T) {
	options := config.Options{Path: "/auto"}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))
	roundTrip(t, conn, randomBytes(t, 64<<10))

	var gets, posts int
	for _, request := range e.server.recorded() {
		switch {
		case request.method == http.MethodGet:
			gets++
		case request.bodyLen >= 0:
			posts++
		}
	}
	if gets != 1 || posts == 0 {
		t.Fatalf("want one download GET and packet uploads, got %d GET and %d packets", gets, posts)
	}
}

func TestPacketUpNeverExceedsTheServerLimit(t *testing.T) {
	limit := config.Range{From: 20000, To: 20000}
	options := config.Options{
		Mode:                 config.ModePacketUp,
		Path:                 "/limit",
		ScMaxEachPostBytes:   &limit,
		ScMinPostsIntervalMs: &config.Range{From: 1, To: 1},
	}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))
	roundTrip(t, conn, randomBytes(t, 1<<20))

	packets := 0
	for _, request := range e.server.recorded() {
		if request.bodyLen < 0 {
			continue
		}
		packets++
		if request.bodyLen > int(limit.To) {
			t.Fatalf("a packet carried %d bytes, the server accepts %d", request.bodyLen, limit.To)
		}
	}
	if packets < (1<<20)/int(limit.To) {
		t.Fatalf("1 MiB went up in %d packets of at most %d bytes", packets, limit.To)
	}
}

func TestPacketUpBatchesSmallWrites(t *testing.T) {
	options := config.Options{
		Mode:                 config.ModePacketUp,
		Path:                 "/batch",
		ScMinPostsIntervalMs: &config.Range{From: 50, To: 50},
	}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))

	const writes = 400
	payload := randomBytes(t, writes*100)
	go func() {
		for i := range writes {
			_, _ = conn.Write(payload[i*100 : (i+1)*100])
		}
	}()
	received := make([]byte, len(payload))
	if _, err := io.ReadFull(conn, received); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(received, payload) {
		t.Fatal("echo differs")
	}

	packets := 0
	for _, request := range e.server.recorded() {
		if request.bodyLen >= 0 {
			packets++
		}
	}
	if packets >= writes/4 {
		t.Fatalf("%d writes became %d requests: writes are not being batched", writes, packets)
	}
}

func TestBytesWrittenJustBeforeCloseStillArrive(t *testing.T) {
	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne} {
		t.Run(mode, func(t *testing.T) {
			options := config.Options{Mode: mode, Path: "/drain"}
			e := startHTTP2(t, options)
			received := make(chan []byte, 1)
			e.server.serve = func(conn io.ReadWriteCloser) {
				data, _ := io.ReadAll(conn)
				received <- data
				_ = conn.Close()
			}
			conn := dialOrFail(t, dialClient(t, e, options))
			payload := randomBytes(t, 200<<10)
			if _, err := conn.Write(payload); err != nil {
				t.Fatal(err)
			}
			// No pause on purpose: this is "send and hang up", and a TCP
			// socket delivers what was sent before the hang-up.
			_ = conn.Close()
			select {
			case data := <-received:
				if !bytes.Equal(data, payload) {
					t.Fatalf("server got %d bytes of %d", len(data), len(payload))
				}
			case <-time.After(10 * time.Second):
				t.Fatal("server never saw the end of the upload")
			}
		})
	}
}

func TestClosingTheConnectionEndsTheSessionOnTheServer(t *testing.T) {
	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne} {
		t.Run(mode, func(t *testing.T) {
			options := config.Options{Mode: mode, Path: "/end"}
			e := startHTTP2(t, options)
			conn := dialOrFail(t, dialClient(t, e, options))
			roundTrip(t, conn, randomBytes(t, 4096))
			_ = conn.Close()

			deadline := time.Now().Add(5 * time.Second)
			for e.server.sessionsEnded.Load() == 0 {
				if time.Now().After(deadline) {
					t.Fatal("the server still holds the session after Close")
				}
				time.Sleep(10 * time.Millisecond)
			}
			if _, err := conn.Read(make([]byte, 1)); err == nil {
				t.Fatal("a closed connection still reads")
			}
			if _, err := conn.Write([]byte("x")); err == nil {
				t.Fatal("a closed connection still writes")
			}
		})
	}
}

func TestPlacements(t *testing.T) {
	cases := map[string]config.Options{
		"session and seq in query": {
			Mode: config.ModePacketUp, SessionPlacement: "query", SeqPlacement: "query",
		},
		"session and seq in headers": {
			Mode: config.ModePacketUp, SessionPlacement: "header", SeqPlacement: "header",
		},
		"session and seq in cookies": {
			Mode: config.ModePacketUp, SessionPlacement: "cookie", SeqPlacement: "cookie",
		},
		"session in path, seq in a custom header": {
			Mode: config.ModePacketUp, SeqPlacement: "header", SeqKey: "X-Order",
		},
		"upload in headers": {
			Mode: config.ModePacketUp, UplinkDataPlacement: "header",
		},
		"upload in cookies": {
			Mode: config.ModePacketUp, UplinkDataPlacement: "cookie",
		},
		"upload by GET in headers": {
			Mode: config.ModePacketUp, UplinkDataPlacement: "header", UplinkHTTPMethod: "get",
			SeqPlacement: "query",
		},
		"stream-up with the session in a header": {
			Mode: config.ModeStreamUp, SessionPlacement: "header",
		},
		"padding as a header": {
			Mode: config.ModePacketUp, XPaddingObfsMode: true, XPaddingPlacement: "header",
		},
		"padding as a cookie": {
			Mode: config.ModePacketUp, XPaddingObfsMode: true, XPaddingPlacement: "cookie",
		},
		"padding in the query": {
			Mode: config.ModePacketUp, XPaddingObfsMode: true, XPaddingPlacement: "query",
		},
		"tokenish padding in a custom header": {
			Mode: config.ModePacketUp, XPaddingObfsMode: true, XPaddingMethod: "tokenish",
			XPaddingPlacement: "queryInHeader", XPaddingHeader: "X-Trace", XPaddingKey: "t",
		},
		"session id from an alphabet": {
			Mode: config.ModePacketUp, SessionIDTable: "base36",
			SessionIDLength: &config.Range{From: 12, To: 20},
		},
		"a path that carries its own query": {
			Mode: config.ModePacketUp, Path: "/place?ed=2048",
		},
	}
	for name, options := range cases {
		t.Run(name, func(t *testing.T) {
			if options.Path == "" {
				options.Path = "/place"
			}
			e := startHTTP2(t, options)
			conn := dialOrFail(t, dialClient(t, e, options))
			// Small enough that a header or a cookie can carry it.
			roundTrip(t, conn, randomBytes(t, 40<<10))
		})
	}
}

func TestRequestsLookLikeABrowser(t *testing.T) {
	options := config.Options{Mode: config.ModePacketUp, Path: "/look", Host: "cdn.example"}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))
	roundTrip(t, conn, randomBytes(t, 1024))

	requests := e.server.recorded()
	if len(requests) < 2 {
		t.Fatalf("expected a GET and at least one POST, got %d requests", len(requests))
	}
	for _, request := range requests {
		agent := request.header.Get("User-Agent")
		if !strings.Contains(agent, "Chrome/") {
			t.Fatalf("User-Agent %q does not look like a browser", agent)
		}
		if strings.Contains(agent, "Go-http-client") {
			t.Fatal("the Go default User-Agent leaked")
		}
		if request.header.Get("Sec-Fetch-Mode") != "cors" {
			t.Fatalf("%s request is missing the fetch() headers", request.method)
		}
		referer := request.header.Get("Referer")
		if !strings.HasPrefix(referer, "https://cdn.example/look/?x_padding=") {
			t.Fatalf("padding should ride in a Referer on the configured host, got %q", referer)
		}
	}
}

func TestACustomUserAgentIsSentAsIs(t *testing.T) {
	options := config.Options{
		Mode: config.ModeStreamOne, Path: "/ua",
		Headers: map[string]string{"User-Agent": "MyClient/1.0", "X-Extra": "1"},
	}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))
	roundTrip(t, conn, randomBytes(t, 512))

	request := e.server.recorded()[0]
	if got := request.header.Get("User-Agent"); got != "MyClient/1.0" {
		t.Fatalf("User-Agent = %q", got)
	}
	if request.header.Get("Sec-Fetch-Mode") != "" {
		t.Fatal("browser headers were added around a User-Agent that is not a browser")
	}
	if request.header.Get("X-Extra") != "1" {
		t.Fatal("custom header lost")
	}
}

func TestStreamRequestsCarryTheGRPCContentType(t *testing.T) {
	for _, disabled := range []bool{false, true} {
		options := config.Options{Mode: config.ModeStreamOne, Path: "/grpc", NoGRPCHeader: disabled}
		e := startHTTP2(t, options)
		conn := dialOrFail(t, dialClient(t, e, options))
		roundTrip(t, conn, randomBytes(t, 512))
		got := e.server.recorded()[0].header.Get("Content-Type")
		if disabled && got != "" {
			t.Fatalf("no_grpc_header is set, Content-Type = %q", got)
		}
		if !disabled && got != "application/grpc" {
			t.Fatalf("Content-Type = %q, want application/grpc", got)
		}
	}
}

func TestAWrongPathIsAnErrorThatNamesTheStatus(t *testing.T) {
	server := config.Options{Mode: config.ModeStreamOne, Path: "/right"}
	e := startHTTP2(t, server)
	client := dialClient(t, e, config.Options{Mode: config.ModeStreamOne, Path: "/wrong"})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx)
	if err == nil {
		// The response may not have arrived when the dial returned; then the
		// first read is where it surfaces.
		defer conn.Close()
		_, err = conn.Read(make([]byte, 1))
	}
	if err == nil || !strings.Contains(err.Error(), "404") {
		t.Fatalf("want an error naming the 404, got %v", err)
	}
}

func TestPaddingTheServerRejectsIsAnError(t *testing.T) {
	server := config.Options{
		Mode: config.ModePacketUp, Path: "/pad",
		XPaddingBytes: &config.Range{From: 2000, To: 3000},
	}
	e := startHTTP2(t, server)
	client := dialClient(t, e, config.Options{Mode: config.ModePacketUp, Path: "/pad"})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx)
	if err == nil {
		defer conn.Close()
		_, err = conn.Read(make([]byte, 1))
	}
	if err == nil || !strings.Contains(err.Error(), "400") {
		t.Fatalf("want an error naming the 400, got %v", err)
	}
}

func TestAnUnreachableServerFailsTheDial(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := M.SocksaddrFromNet(listener.Addr())
	_ = listener.Close()

	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne} {
		transport, err := NewClient(context.Background(), N.SystemDialer, addr,
			config.Options{Mode: mode}, nil)
		if err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_, err = transport.DialContext(ctx)
		cancel()
		if err == nil {
			t.Fatalf("%s: dialing a closed port succeeded", mode)
		}
		_ = transport.Close()
	}
}

// blackhole accepts TCP connections and never says a word, which is what a
// server behind a dropping firewall looks like after the handshake.
func blackhole(t *testing.T) M.Socksaddr {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var held []net.Conn
	var mu sync.Mutex
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			mu.Lock()
			held = append(held, conn)
			mu.Unlock()
		}
	}()
	t.Cleanup(func() {
		_ = listener.Close()
		mu.Lock()
		defer mu.Unlock()
		for _, conn := range held {
			_ = conn.Close()
		}
	})
	return M.SocksaddrFromNet(listener.Addr())
}

func TestTheCallersDeadlineBoundsTheDial(t *testing.T) {
	transport, err := NewClient(context.Background(), N.SystemDialer, blackhole(t),
		config.Options{Mode: config.ModeStreamOne},
		&stdTLS{insecureTLS()})
	if err != nil {
		t.Fatal(err)
	}
	defer transport.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	started := time.Now()
	_, err = transport.DialContext(ctx)
	if err == nil {
		t.Fatal("a TLS handshake with a silent server succeeded")
	}
	if elapsed := time.Since(started); elapsed > 3*time.Second {
		t.Fatalf("the dial ignored a 300 ms deadline for %v", elapsed)
	}
}

func TestTheStreamOutlivesTheDialContext(t *testing.T) {
	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne} {
		t.Run(mode, func(t *testing.T) {
			options := config.Options{Mode: mode, Path: "/detach"}
			e := startHTTP2(t, options)
			client := dialClient(t, e, options)

			ctx, cancel := context.WithCancel(context.Background())
			conn, err := client.DialContext(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			// What every caller with `defer cancel()` does the moment the dial
			// returns. The proxied connection has to survive it.
			cancel()
			time.Sleep(50 * time.Millisecond)
			roundTrip(t, conn, randomBytes(t, 256<<10))
		})
	}
}

func TestManyConnectionsShareFewHTTPConnections(t *testing.T) {
	options := config.Options{
		Mode: config.ModeStreamOne, Path: "/mux",
		Xmux: &config.Xmux{MaxConnections: &config.Range{From: 2, To: 2}},
	}
	e := startHTTP2(t, options)
	client := dialClient(t, e, options)

	var group sync.WaitGroup
	for range 24 {
		group.Add(1)
		go func() {
			defer group.Done()
			conn := dialOrFail(t, client)
			roundTrip(t, conn, randomBytes(t, 32<<10))
		}()
	}
	group.Wait()
	if accepted := e.listener.accepted.Load(); accepted > 2 {
		t.Fatalf("24 proxied connections opened %d TCP connections, max_connections is 2", accepted)
	}
}

func TestAConnectionIsRetiredAfterItsQuotaOfRequests(t *testing.T) {
	options := config.Options{
		Mode: config.ModePacketUp, Path: "/quota",
		ScMaxEachPostBytes:   &config.Range{From: 4096, To: 4096},
		ScMinPostsIntervalMs: &config.Range{From: 1, To: 1},
		Xmux: &config.Xmux{
			MaxConcurrency:   &config.Range{From: 1, To: 1},
			HMaxRequestTimes: &config.Range{From: 5, To: 5},
		},
	}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))
	// Forty packets against a quota of five requests per connection.
	roundTrip(t, conn, randomBytes(t, 40*4096))

	if accepted := e.listener.accepted.Load(); accepted < 3 {
		t.Fatalf("the upload stayed on %d TCP connection(s) despite h_max_request_times=5", accepted)
	}
}

// sing-box closes a transport when the default network interface changes, and
// expects it to carry the next connection over the new network. On Android
// that happens within the first second of every tunnel.
func TestCloseIsAResetNotAnEnd(t *testing.T) {
	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne} {
		t.Run(mode, func(t *testing.T) {
			options := config.Options{Mode: mode, Path: "/reset"}
			e := startHTTP2(t, options)
			client := dialClient(t, e, options)
			before := dialOrFail(t, client)
			roundTrip(t, before, randomBytes(t, 1024))

			_ = client.Close()

			// What was open is gone: it rode the old network.
			done := make(chan error, 1)
			go func() {
				_, err := before.Read(make([]byte, 1))
				done <- err
			}()
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("a connection survived the reset")
				}
			case <-time.After(5 * time.Second):
				t.Fatal("a read is still blocked after the reset")
			}

			// What comes next works, on a fresh HTTP connection.
			accepted := e.listener.accepted.Load()
			after := dialOrFail(t, client)
			roundTrip(t, after, randomBytes(t, 64<<10))
			if e.listener.accepted.Load() == accepted {
				t.Fatal("the new connection reused an HTTP connection from before the reset")
			}

			// And again: interfaces change more than once in a session.
			_ = client.Close()
			_ = client.Close()
			again := dialOrFail(t, client)
			roundTrip(t, again, randomBytes(t, 1024))
		})
	}
}

func TestDeadlinesAreDeclaredUnsupported(t *testing.T) {
	options := config.Options{Mode: config.ModeStreamOne, Path: "/deadline"}
	e := startHTTP2(t, options)
	conn := dialOrFail(t, dialClient(t, e, options))
	if err := conn.SetReadDeadline(time.Now()); err == nil {
		t.Fatal("SetReadDeadline pretended to work; sing-box would not wrap the connection")
	}
	if needs, ok := conn.(interface{ NeedAdditionalReadDeadline() bool }); !ok || !needs.NeedAdditionalReadDeadline() {
		t.Fatal("the connection does not ask sing-box for deadline emulation")
	}
}
