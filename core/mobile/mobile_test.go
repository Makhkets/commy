package mobile_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Makhkets/commy/core/mobile"
)

// The app's end of the probe: the configuration goes in as a string, and
// the answer comes back as a JSON object the Kotlin side can read.
func TestURLTestOutboundsAnswersJSON(t *testing.T) {
	page, seen := probePage(t)
	proxy := socksServer(t)
	refused := closedPort(t)

	document := fmt.Sprintf(`{
		"log": {"disabled": true},
		"outbounds": [
			{"type": "socks", "tag": "node-up", "server": "127.0.0.1", "server_port": %d},
			{"type": "socks", "tag": "node-down", "server": "127.0.0.1", "server_port": %d}
		]
	}`, proxy, refused)

	delays := urlTest(t, document, page+"/generate_204")
	if delays["node-up"] <= 0 {
		t.Errorf("the reachable server was not measured: %v", delays)
	}
	if delays["node-down"] != 0 {
		t.Errorf("a refused server has a delay: %v", delays)
	}
	expectGet(t, seen)
}

// A server named by host name is resolved by the system resolver: "localhost"
// here, where on Android it is every server a panel hands out — and where
// sing-box's own "local" would read an /etc/resolv.conf that is not there.
func TestURLTestOutboundsResolvesServerNames(t *testing.T) {
	addresses, err := net.DefaultResolver.LookupNetIP(context.Background(), "ip", "localhost")
	if err != nil || len(addresses) == 0 {
		t.Skip("this machine does not resolve localhost")
	}
	page, seen := probePage(t)
	// Both loopbacks, so whichever address the name comes back as, it
	// reaches the server.
	proxy := socksServer(t)

	document := fmt.Sprintf(`{
		"log": {"disabled": true},
		"dns": {"servers": [{"type": "local", "tag": "dns-direct"}]},
		"outbounds": [
			{"type": "socks", "tag": "node-named", "server": "localhost", "server_port": %d}
		],
		"route": {"default_domain_resolver": {"server": "dns-direct"}}
	}`, proxy)

	delays := urlTest(t, document, page+"/generate_204")
	if delays["node-named"] <= 0 {
		t.Errorf("the server behind a host name was not measured: %v "+
			"(localhost is %v here)", delays, addresses)
	}
	expectGet(t, seen)
}

// urlTest runs the exported function and reads its answer. Ten seconds a
// server: a race-detector build on a shared CI runner is slow.
func urlTest(t *testing.T, document string, link string) map[string]int {
	t.Helper()
	answer, err := mobile.URLTestOutbounds(document, link, 10000)
	if err != nil {
		t.Fatalf("URLTestOutbounds: %v", err)
	}
	var delays map[string]int
	if err := json.Unmarshal([]byte(answer), &delays); err != nil {
		t.Fatalf("not a JSON object of delays: %q", answer)
	}
	return delays
}

// probePage answers 204 and reports the method of every request it gets.
func probePage(t *testing.T) (string, <-chan string) {
	t.Helper()
	seen := make(chan string, 8)
	page := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case seen <- r.Method:
		default:
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(page.Close)
	return page.URL, seen
}

// expectGet fails unless the probe page was asked, and asked with GET. It
// never waits long: a request that did not arrive is a failure to report,
// not a reason to hang the whole run.
func expectGet(t *testing.T, seen <-chan string) {
	t.Helper()
	select {
	case method := <-seen:
		if method != http.MethodGet {
			t.Errorf("the probe page was asked with %s", method)
		}
	case <-time.After(5 * time.Second):
		t.Error("the probe page was never asked")
	}
}

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

// socksServer is a minimal SOCKS5 proxy: no authentication, CONNECT only. It
// listens on 127.0.0.1 and, where the machine has it, on [::1] at the same
// port.
func socksServer(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listeners := []net.Listener{listener}
	if v6, err := net.Listen("tcp", fmt.Sprintf("[::1]:%d", port)); err == nil {
		listeners = append(listeners, v6)
	}
	for _, each := range listeners {
		t.Cleanup(func() { _ = each.Close() })
		go func() {
			for {
				conn, err := each.Accept()
				if err != nil {
					return
				}
				go serveSocks(conn)
			}
		}()
	}
	return port
}

func serveSocks(conn net.Conn) {
	defer conn.Close()
	buf := make([]byte, 262)
	// Greeting: version, method count, methods. Answer "no authentication".
	if _, err := readFull(conn, buf[:2]); err != nil {
		return
	}
	if _, err := readFull(conn, buf[:buf[1]]); err != nil {
		return
	}
	if _, err := conn.Write([]byte{5, 0}); err != nil {
		return
	}
	// Request: version, CONNECT, reserved, address type.
	if _, err := readFull(conn, buf[:4]); err != nil {
		return
	}
	var host string
	switch buf[3] {
	case 1:
		if _, err := readFull(conn, buf[:4]); err != nil {
			return
		}
		host = net.IP(buf[:4]).String()
	case 3:
		if _, err := readFull(conn, buf[:1]); err != nil {
			return
		}
		length := int(buf[0])
		if _, err := readFull(conn, buf[:length]); err != nil {
			return
		}
		host = string(buf[:length])
	default:
		return
	}
	if _, err := readFull(conn, buf[:2]); err != nil {
		return
	}
	port := int(buf[0])<<8 | int(buf[1])
	target, err := net.Dial("tcp", net.JoinHostPort(host, fmt.Sprint(port)))
	if err != nil {
		_, _ = conn.Write([]byte{5, 5, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer target.Close()
	if _, err := conn.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}
	go func() {
		_, _ = copyAll(target, conn)
		_ = target.Close()
	}()
	_, _ = copyAll(conn, target)
}

func readFull(conn net.Conn, buf []byte) (int, error) {
	read := 0
	for read < len(buf) {
		n, err := conn.Read(buf[read:])
		read += n
		if err != nil {
			return read, err
		}
	}
	return read, nil
}

func copyAll(dst net.Conn, src net.Conn) (int64, error) {
	buf := make([]byte, 32*1024)
	var total int64
	for {
		n, err := src.Read(buf)
		if n > 0 {
			if _, werr := dst.Write(buf[:n]); werr != nil {
				return total, werr
			}
			total += int64(n)
		}
		if err != nil {
			return total, err
		}
	}
}
