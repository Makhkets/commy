package latency_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/Makhkets/commy/core/latency"
	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// A GET through a real proxy protocol, a GET out of the machine directly, and
// a server that refuses: two numbers and a zero, and the probe page saw GETs.
func TestMeasureTimesAGetThroughEachOutbound(t *testing.T) {
	page := newProbePage(t)
	proxyPort := startShadowsocksServer(t)
	closed := closedPort(t)

	document := fmt.Sprintf(`{
		"log": {"disabled": true},
		"outbounds": [
			{"type": "shadowsocks", "tag": "ss", "server": "127.0.0.1", "server_port": %d,
			 "method": "aes-128-gcm", "password": "commy"},
			{"type": "direct", "tag": "plain"},
			{"type": "socks", "tag": "refused", "server": "127.0.0.1", "server_port": %d}
		]
	}`, proxyPort, closed)

	delays := measure(t, document, page.URL+"/generate_204", 5*time.Second)

	if delays["ss"] == 0 {
		t.Errorf("the server behind shadowsocks was not measured: %v", delays)
	}
	if delays["plain"] == 0 {
		t.Errorf("the direct outbound was not measured: %v", delays)
	}
	if delays["refused"] != 0 {
		t.Errorf("a server that refused has a delay of %d ms", delays["refused"])
	}
	if methods := page.methods(); len(methods) < 2 {
		t.Errorf("the probe page saw %v", methods)
	} else {
		for _, method := range methods {
			if method != http.MethodGet {
				t.Errorf("the probe page was asked with %s, not GET", method)
			}
		}
	}
}

// Every server has its own timeout, counted from when its turn comes: twelve
// that never answer, two waves of ten, and the one that works is still there.
func TestMeasureGivesEachServerItsOwnTimeout(t *testing.T) {
	page := newProbePage(t)
	silent := silentServer(t)

	outbounds := `{"type": "direct", "tag": "plain"}`
	for i := 0; i < 12; i++ {
		outbounds += fmt.Sprintf(
			`, {"type": "socks", "tag": "silent-%d", "server": "127.0.0.1", "server_port": %d}`,
			i, silent,
		)
	}
	document := fmt.Sprintf(`{"log": {"disabled": true}, "outbounds": [%s]}`, outbounds)

	const timeout = 400 * time.Millisecond
	started := time.Now()
	delays := measure(t, document, page.URL+"/generate_204", timeout)
	took := time.Since(started)

	if delays["plain"] == 0 {
		t.Errorf("the working outbound was lost among the silent ones: %v", delays)
	}
	for i := 0; i < 12; i++ {
		if delay := delays[fmt.Sprintf("silent-%d", i)]; delay != 0 {
			t.Errorf("silent-%d answered in %d ms", i, delay)
		}
	}
	// Two waves of the timeout, not twelve, and not one: the eleventh and
	// twelfth wait for a slot and then get their full time.
	if took < 2*timeout || took > 6*timeout {
		t.Errorf("thirteen servers took %v with a %v timeout", took, timeout)
	}
}

// A configuration the core refuses is an error, not a list of zeros.
func TestMeasureConfigRefusesABrokenConfig(t *testing.T) {
	ctx := include.Context(context.Background())
	_, err := latency.MeasureConfig(ctx, `{"outbounds": [{"type": "no-such-type", "tag": "x"}]}`,
		"http://127.0.0.1:1/", time.Second)
	if err == nil {
		t.Fatal("an outbound type the core does not know was accepted")
	}
}

func measure(t *testing.T, document string, link string, timeout time.Duration) map[string]uint16 {
	t.Helper()
	ctx := include.Context(context.Background())
	answer, err := latency.MeasureConfig(ctx, document, link, timeout)
	if err != nil {
		t.Fatalf("measure: %v", err)
	}
	var delays map[string]uint16
	if err := json.Unmarshal([]byte(answer), &delays); err != nil {
		t.Fatalf("the answer is not a JSON object of delays: %q", answer)
	}
	return delays
}

type probePage struct {
	*httptest.Server
	access sync.Mutex
	seen   []string
}

func newProbePage(t *testing.T) *probePage {
	t.Helper()
	page := &probePage{}
	page.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		page.access.Lock()
		page.seen = append(page.seen, r.Method)
		page.access.Unlock()
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(page.Close)
	return page
}

func (p *probePage) methods() []string {
	p.access.Lock()
	defer p.access.Unlock()
	return append([]string(nil), p.seen...)
}

func startShadowsocksServer(t *testing.T) int {
	t.Helper()
	port := closedPort(t)
	document := fmt.Sprintf(`{
		"log": {"disabled": true},
		"inbounds": [{"type": "shadowsocks", "listen": "127.0.0.1", "listen_port": %d,
		              "method": "aes-128-gcm", "password": "commy"}],
		"outbounds": [{"type": "direct"}]
	}`, port)
	ctx, cancel := context.WithCancel(include.Context(context.Background()))
	t.Cleanup(cancel)
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(document))
	if err != nil {
		t.Fatal(err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		t.Fatal(err)
	}
	if err := instance.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = instance.Close() })
	return port
}

// closedPort is a port nothing listens on, for a moment.
func closedPort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	_ = listener.Close()
	return port
}

// silentServer accepts connections and never says a word.
func silentServer(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var held []net.Conn
	var access sync.Mutex
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			access.Lock()
			held = append(held, conn)
			access.Unlock()
		}
	}()
	t.Cleanup(func() {
		_ = listener.Close()
		access.Lock()
		defer access.Unlock()
		for _, conn := range held {
			_ = conn.Close()
		}
	})
	return listener.Addr().(*net.TCPAddr).Port
}
