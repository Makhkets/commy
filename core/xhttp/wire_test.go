package xhttp

import (
	"math/rand/v2"
	"net/http"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	"golang.org/x/net/http2/hpack"
)

func TestRepeatXPaddingIsExactlyAsLongAsAsked(t *testing.T) {
	for _, length := range []int{1, 100, 1000} {
		value := generatePadding(config.PaddingRepeatX, length)
		if len(value) != length {
			t.Fatalf("asked for %d, got %d", length, len(value))
		}
		// The whole point of 'X': Huffman coding must not change the length.
		if got := int(hpack.HuffmanEncodeLength(value)); got != length {
			t.Fatalf("%d bytes of padding are %d bytes on an HTTP/2 wire", length, got)
		}
	}
	if generatePadding(config.PaddingRepeatX, 0) != "" {
		t.Fatal("zero-length padding is not empty")
	}
}

func TestTokenishPaddingLandsOnItsHuffmanLength(t *testing.T) {
	for _, target := range []int{10, 100, 500, 1000} {
		for range 20 {
			value := generatePadding(config.PaddingTokenish, target)
			got := int(hpack.HuffmanEncodeLength(value))
			if got < target-paddingTolerance || got > target+paddingTolerance {
				t.Fatalf("target %d, Huffman length %d", target, got)
			}
			if strings.Trim(value, charsetBase62) != "" {
				t.Fatalf("not base62: %q", value)
			}
		}
	}
}

func TestSessionIDs(t *testing.T) {
	plain, err := config.Options{}.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for range 1000 {
		id := newSessionID(&plain)
		if len(id) != 36 || id[14] != '4' || !strings.ContainsRune("89ab", rune(id[19])) {
			t.Fatalf("not a version 4 UUID: %q", id)
		}
		if seen[id] {
			t.Fatalf("session id repeated: %q", id)
		}
		seen[id] = true
	}

	table, err := config.Options{
		SessionIDTable:  "hex",
		SessionIDLength: &config.Range{From: 16, To: 24},
	}.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	for range 200 {
		id := newSessionID(&table)
		if len(id) < 16 || len(id) > 24 || strings.Trim(id, "0123456789abcdef") != "" {
			t.Fatalf("id %q does not come from the configured alphabet and length", id)
		}
	}
}

func TestBrowserVersionsFollowTheCalendar(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	early := newBrowserStrings(time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC), rng)
	late := newBrowserStrings(time.Date(2028, 3, 1, 0, 0, 0, 0, time.UTC), rng)
	if early.chromeUA == late.chromeUA || early.firefoxUA == late.firefoxUA {
		t.Fatal("two years on, the client still announces the same browser")
	}
	// Before the anchor dates the arithmetic would go backwards; it must not.
	old := newBrowserStrings(time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC), rng)
	if !strings.Contains(old.chromeUA, "Chrome/144.") || !strings.Contains(old.curlUA, "curl/8.0.0") {
		t.Fatalf("clock before the anchor: %q, %q", old.chromeUA, old.curlUA)
	}
	if !strings.Contains(early.chromeBrands, `"Chromium";v="`) ||
		!strings.Contains(early.chromeBrands, `"Google Chrome";v="`) ||
		!strings.Contains(early.chromeBrands, `Brand";v="`) {
		t.Fatalf("brand list: %s", early.chromeBrands)
	}
}

func TestNamedBrowsersAndTheGoDefault(t *testing.T) {
	for _, name := range []string{browserFirefox, browserSafari, browserEdge} {
		header := requestHeader(map[string]string{"User-Agent": name})
		if got := header.Get("User-Agent"); got == name || !strings.HasPrefix(got, "Mozilla/5.0") {
			t.Fatalf("%s: User-Agent = %q", name, got)
		}
		if header.Get("Sec-Fetch-Site") != "same-origin" {
			t.Fatalf("%s: fetch headers missing", name)
		}
	}
	if header := requestHeader(map[string]string{"User-Agent": browserGolang}); len(header.Values("User-Agent")) != 0 {
		t.Fatal(`"golang" should leave User-Agent to net/http`)
	}
	curl := requestHeader(map[string]string{"User-Agent": browserCurl})
	if !strings.HasPrefix(curl.Get("User-Agent"), "curl/8.") || curl.Get("Sec-Fetch-Mode") != "" {
		t.Fatalf("curl does not send fetch headers: %v", curl)
	}
	// What the configuration sets wins over what the browser profile would add.
	custom := requestHeader(map[string]string{"Accept": "text/plain", "Cache-Control": "max-age=0"})
	if custom.Get("Accept") != "text/plain" || custom.Get("Cache-Control") != "max-age=0" {
		t.Fatalf("configured headers were overwritten: %v", custom)
	}
}

func TestPaddingIsBuiltBeforeTheSessionGoesIntoThePath(t *testing.T) {
	options, err := config.Options{Path: "/p?keep=1"}.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	target := baseURL(&options, true, "example.com")
	request, err := http.NewRequest(http.MethodGet, target.String(), nil)
	if err != nil {
		t.Fatal(err)
	}
	fillStreamRequest(request, &options, "session-1")
	if request.URL.Path != "/p/session-1" || request.URL.RawQuery != "keep=1" {
		t.Fatalf("request URL: %s", request.URL)
	}
	referer := request.Header.Get("Referer")
	if !strings.HasPrefix(referer, "https://example.com/p/?x_padding=X") || strings.Contains(referer, "session-1") {
		t.Fatalf("Referer: %q", referer)
	}
}

// A tunnel lives for hours and opens thousands of connections. Whatever a
// connection starts, closing it has to stop.
func TestNothingIsLeftRunning(t *testing.T) {
	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp, config.ModeStreamOne} {
		options := config.Options{Mode: mode, Path: "/leak"}
		e := startHTTP2(t, options)
		client := dialClient(t, e, options)

		// Fill the pool first: by default XMUX opens three HTTP connections,
		// and each brings goroutines that are meant to stay. The test server
		// runs in this process, so its half of every connection counts too.
		for range 6 {
			conn := dialOrFail(t, client)
			roundTrip(t, conn, randomBytes(t, 1024))
			_ = conn.Close()
		}
		time.Sleep(300 * time.Millisecond)
		before := runtime.NumGoroutine()

		for range 30 {
			conn := dialOrFail(t, client)
			roundTrip(t, conn, randomBytes(t, 8192))
			_ = conn.Close()
		}
		deadline := time.Now().Add(10 * time.Second)
		for runtime.NumGoroutine() > before+4 {
			if time.Now().After(deadline) {
				t.Fatalf("%s: %d goroutines before thirty connections, %d after",
					mode, before, runtime.NumGoroutine())
			}
			time.Sleep(50 * time.Millisecond)
		}
	}
}
