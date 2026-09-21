//go:build commy_overlay

package xhttp_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"

	"github.com/Makhkets/commy/core/xhttp"
	"github.com/Makhkets/commy/core/xhttp/config"
)

// This test needs the build overlay, because it goes through sing-box itself:
//
//	GODEBUG=goindex=0 go test -overlay="$(go run ./cmd/overlaygen)" \
//	    -tags "<core tags>,commy_overlay" ./xhttp/
//
// It is what proves the two upstream switches were really reached — that a
// document with "type": "xhttp" is decoded by sing-box's own option machinery
// and that the VLESS outbound it builds carries traffic:
//
//	http client -> mixed inbound -> VLESS outbound over XHTTP
//	    -> fake Xray (HTTP/2, TLS) -> VLESS inbound -> direct -> target
const uuid = "4f6a3b2c-9d1e-4c5a-8b7f-0123456789ab"

func freePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func TestSingBoxCarriesTrafficOverXHTTP(t *testing.T) {
	for _, mode := range []string{"auto", "packet-up", "stream-up", "stream-one"} {
		t.Run(mode, func(t *testing.T) {
			payload := make([]byte, 2<<20)
			if _, err := rand.Read(payload); err != nil {
				t.Fatal(err)
			}
			target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body, _ := io.ReadAll(r.Body)
				_, _ = w.Write(body) // echo the upload back as the download
			}))
			defer target.Close()

			vlessPort, mixedPort := freePort(t), freePort(t)
			serverOptions := config.Options{Mode: mode, Path: "/e2e"}
			fake := xhttp.StartFakeXrayHTTP2(t, serverOptions, func(conn io.ReadWriteCloser) {
				defer conn.Close()
				upstream, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", vlessPort))
				if err != nil {
					return
				}
				defer upstream.Close()
				go func() { _, _ = io.Copy(upstream, conn) }()
				_, _ = io.Copy(conn, upstream)
			})

			document := fmt.Sprintf(`{
			  "log": {"level": "debug"},
			  "inbounds": [
			    {"type": "mixed", "tag": "in", "listen": "127.0.0.1", "listen_port": %d},
			    {"type": "vless", "tag": "vless-in", "listen": "127.0.0.1", "listen_port": %d,
			     "users": [{"uuid": %q}]}
			  ],
			  "outbounds": [
			    {"type": "vless", "tag": "proxy", "server": "127.0.0.1", "server_port": %d,
			     "uuid": %q,
			     "tls": {"enabled": true, "server_name": "xhttp.test", "insecure": true},
			     "transport": {"type": "xhttp", "mode": %q, "path": "/e2e", "host": "xhttp.test",
			                   "x_padding_bytes": "100-1000", "sc_min_posts_interval_ms": 5}},
			    {"type": "direct", "tag": "direct"}
			  ],
			  "route": {"rules": [
			    {"inbound": "in", "outbound": "proxy"},
			    {"inbound": "vless-in", "outbound": "direct"}
			  ]}
			}`, mixedPort, vlessPort, uuid, fake.Addr.Port, uuid, mode)

			ctx := include.Context(context.Background())
			options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(document))
			if err != nil {
				t.Fatalf("sing-box refused the document: %v", err)
			}
			instance, err := box.New(box.Options{Context: ctx, Options: options})
			if err != nil {
				t.Fatalf("box.New: %v", err)
			}
			if err := instance.Start(); err != nil {
				t.Fatalf("start: %v", err)
			}
			defer instance.Close()

			proxy, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", mixedPort))
			client := &http.Client{
				Transport: &http.Transport{Proxy: http.ProxyURL(proxy)},
				Timeout:   30 * time.Second,
			}
			response, err := client.Post(target.URL, "application/octet-stream", bytes.NewReader(payload))
			if err != nil {
				t.Fatalf("request through the tunnel: %v", err)
			}
			defer response.Body.Close()
			echoed, err := io.ReadAll(response.Body)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(echoed, payload) {
				t.Fatalf("sent %d bytes, got %d back, contents differ", len(payload), len(echoed))
			}
			if fake.RequestCount() == 0 {
				t.Fatal("the traffic did not go through the XHTTP server")
			}

			// What Android does within a second of every start, and on every
			// move between Wi-Fi and mobile: the default interface is reported,
			// and sing-box tells each outbound, which closes its transport. The
			// first build of this transport took that Close for the end and
			// refused every dial after it; nothing on a desktop ever showed it.
			proxy2, found := instance.Outbound().Outbound("proxy")
			if !found {
				t.Fatal("no outbound tagged proxy")
			}
			listener, ok := proxy2.(adapter.InterfaceUpdateListener)
			if !ok {
				t.Fatal("the VLESS outbound no longer listens for interface updates")
			}
			listener.InterfaceUpdated()
			client.CloseIdleConnections()
			again, err := client.Post(target.URL, "application/octet-stream", bytes.NewReader(payload[:64<<10]))
			if err != nil {
				t.Fatalf("after an interface update: %v", err)
			}
			defer again.Body.Close()
			echoedAgain, err := io.ReadAll(again.Body)
			if err != nil || !bytes.Equal(echoedAgain, payload[:64<<10]) {
				t.Fatalf("after an interface update: %d bytes back, err %v", len(echoedAgain), err)
			}
		})
	}
}

func TestSingBoxRefusesAnXHTTPBlockItCannotHonour(t *testing.T) {
	cases := map[string]string{
		// Not an empty object: sing-box drops those before it looks at keys.
		"unknown field": `{"type": "xhttp", "download": {"server": "other.example"}}`,
		"bad mode":      `{"type": "xhttp", "mode": "stream-down"}`,
		"bad range":     `{"type": "xhttp", "x_padding_bytes": "a-b"}`,
	}
	for name, transport := range cases {
		document := fmt.Sprintf(`{"outbounds": [{"type": "vless", "tag": "p", "server": "127.0.0.1",
		  "server_port": 443, "uuid": %q, "transport": %s}]}`, uuid, transport)
		ctx := include.Context(context.Background())
		options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(document))
		if err == nil {
			var instance *box.Box
			instance, err = box.New(box.Options{Context: ctx, Options: options})
			if err == nil {
				_ = instance.Close()
			}
		}
		if err == nil {
			t.Errorf("%s: accepted", name)
		} else if !strings.Contains(strings.ToLower(err.Error()), "xhttp") &&
			!strings.Contains(err.Error(), "transport") && !strings.Contains(err.Error(), "download") {
			t.Errorf("%s: the error does not say where: %v", name, err)
		}
	}
}
