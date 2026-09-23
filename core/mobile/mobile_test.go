package mobile_test

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Makhkets/commy/core/mobile"
)

// The app's end of the probe: the configuration goes in as a string, the
// answer comes back as a JSON object the Kotlin side can read, and a server
// named by host name is resolved by the system resolver — "localhost" here,
// where on Android it is every server a panel hands out.
func TestURLTestOutboundsAnswersJSON(t *testing.T) {
	seen := make(chan string, 4)
	page := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen <- r.Method
		w.WriteHeader(http.StatusNoContent)
	}))
	defer page.Close()

	proxy := socksServer(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	refused := listener.Addr().(*net.TCPAddr).Port
	_ = listener.Close()

	document := fmt.Sprintf(`{
		"log": {"disabled": true},
		"dns": {"servers": [{"type": "local", "tag": "dns-direct"}]},
		"outbounds": [
			{"type": "socks", "tag": "node-up", "server": "localhost", "server_port": %d},
			{"type": "socks", "tag": "node-down", "server": "127.0.0.1", "server_port": %d}
		],
		"route": {"default_domain_resolver": {"server": "dns-direct"}}
	}`, proxy, refused)

	answer, err := mobile.URLTestOutbounds(document, page.URL+"/generate_204", 3000)
	if err != nil {
		t.Fatalf("URLTestOutbounds: %v", err)
	}
	var delays map[string]int
	if err := json.Unmarshal([]byte(answer), &delays); err != nil {
		t.Fatalf("not a JSON object of delays: %q", answer)
	}
	if delays["node-up"] <= 0 {
		t.Errorf("the server behind a host name was not measured: %s", answer)
	}
	if delays["node-down"] != 0 {
		t.Errorf("a refused server has a delay: %s", answer)
	}
	if method := <-seen; method != http.MethodGet {
		t.Errorf("the probe page was asked with %s", method)
	}
}

// socksServer is a minimal SOCKS5 proxy: no authentication, CONNECT only.
func socksServer(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
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
			go serveSocks(conn)
		}
	}()
	return listener.Addr().(*net.TCPAddr).Port
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
