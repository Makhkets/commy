package xhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// Xray's downloadSettings: the GET of stream-up and packet-up goes to a second
// route — its own address, TLS, HTTP version and options — and meets its
// uploads at the server by session id. The fake server's twin is that second
// front door: its own options, the same sessions.

// startSplit serves [main] on one endpoint and its twin, dressed by
// [download], on another, and returns a client with a download route.
func startSplit(
	t *testing.T,
	start func(testing.TB, *fakeXray) *endpoint,
	startDownload func(testing.TB, *fakeXray) *endpoint,
	main, download config.Options,
) (up, down *endpoint, client *Client) {
	t.Helper()
	server := newFakeXray(t, main)
	up = start(t, server)
	// The twin checks what the download route sends against the download
	// route's own options, and pairs it with the main route's uploads.
	twinOptions := download
	twinOptions.Mode = main.Mode
	down = startDownload(t, server.twin(twinOptions))
	client = dialClient(t, up, withDownload(main, down, download))
	return up, down, client
}

func countMethods(requests []recordedRequest) (gets, uploads int) {
	for _, request := range requests {
		if request.method == http.MethodGet && request.bodyLen <= 0 {
			gets++
		} else {
			uploads++
		}
	}
	return gets, uploads
}

func TestTheDownloadTakesItsOwnRoute(t *testing.T) {
	type server = func(testing.TB, *fakeXray) *endpoint
	routes := []struct {
		name     string
		up, down server
	}{
		{"h2 up, h1 down", serveHTTP2, serveHTTP1},
		{"h1 up, h2 down", serveHTTP1, serveHTTP2},
		{"h2 up, h3 down", serveHTTP2, serveHTTP3},
		{"h3 up, h2 down", serveHTTP3, serveHTTP2},
	}
	for _, mode := range []string{config.ModePacketUp, config.ModeStreamUp} {
		for _, route := range routes {
			t.Run(mode+"/"+route.name, func(t *testing.T) {
				up, down, client := startSplit(t, route.up, route.down,
					config.Options{Mode: mode, Path: "/xh"}, config.Options{Path: "/xh"})

				roundTrip(t, dialOrFail(t, client), randomBytes(t, 1<<20))

				downGets, downUploads := countMethods(down.server.recorded())
				upGets, upUploads := countMethods(up.server.recorded())
				if downGets != 1 || downUploads != 0 {
					t.Fatalf("download route saw %d GETs and %d uploads, want 1 and 0", downGets, downUploads)
				}
				if upGets != 0 || upUploads == 0 {
					t.Fatalf("main route saw %d GETs and %d uploads, want 0 and some", upGets, upUploads)
				}
			})
		}
	}
}

func TestTheDownloadRouteIsDressedByItsOwnOptions(t *testing.T) {
	// The main route: its path, the session id in a header. The download
	// route: another path, the id in the query, obfuscated padding in a
	// header. The twin refuses a GET that does not follow the download
	// route's options — so a GET dressed by the main route's would fail.
	main := config.Options{
		Mode:             config.ModePacketUp,
		Path:             "/up",
		SessionPlacement: config.PlacementHeader,
	}
	download := config.Options{
		Path:              "/down",
		SessionPlacement:  config.PlacementQuery,
		XPaddingObfsMode:  true,
		XPaddingPlacement: config.PlacementHeader,
		Headers:           map[string]string{"X-Edge": "cdn"},
	}
	up, down, client := startSplit(t, serveHTTP2, serveHTTP2, main, download)

	roundTrip(t, dialOrFail(t, client), randomBytes(t, 64<<10))

	gets := down.server.recorded()
	if len(gets) != 1 || !strings.HasPrefix(gets[0].path, "/down") {
		t.Fatalf("download requests: %+v", gets)
	}
	if gets[0].header.Get("X-Edge") != "cdn" {
		t.Fatal("the download route's own headers were not sent")
	}
	for _, request := range up.server.recorded() {
		if !strings.HasPrefix(request.path, "/up") {
			t.Fatalf("an upload went to %s", request.path)
		}
		if request.header.Get("X-Edge") != "" {
			t.Fatal("the main route sent the download route's headers")
		}
	}
}

func TestEachRouteHasAPoolOfItsOwn(t *testing.T) {
	// One connection for every download, the default three for uploads.
	one := config.Range{From: 1, To: 1}
	up, down, client := startSplit(t, serveHTTP2, serveHTTP2,
		config.Options{Mode: config.ModeStreamUp, Path: "/xh"},
		config.Options{Path: "/xh", Xmux: &config.Xmux{MaxConnections: &one}})

	for range 10 {
		roundTrip(t, dialOrFail(t, client), randomBytes(t, 4<<10))
	}

	if accepted := down.listener.accepted.Load(); accepted != 1 {
		t.Fatalf("download route opened %d connections, want 1", accepted)
	}
	if accepted := up.listener.accepted.Load(); accepted < 1 || accepted > 3 {
		t.Fatalf("main route opened %d connections, want 1 to 3", accepted)
	}
}

func TestAFailedDownloadIsAnErrorAndReleasesBothRoutes(t *testing.T) {
	server := newFakeXray(t, config.Options{Mode: config.ModePacketUp, Path: "/xh"})
	up := serveHTTP2(t, server)
	// A download route to a path the server does not serve: a 404.
	down := serveHTTP2(t, server.twin(config.Options{Mode: config.ModePacketUp, Path: "/xh"}))
	client := dialClient(t, up, withDownload(
		config.Options{Mode: config.ModePacketUp, Path: "/xh"}, down, config.Options{Path: "/elsewhere"}))

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx)
	if err == nil {
		// The response may not have arrived when the dial returned; then the
		// first read is where it surfaces, and closing is what releases.
		_, err = conn.Read(make([]byte, 1))
		_ = conn.Close()
	}
	if err == nil || !strings.Contains(err.Error(), "404") {
		t.Fatalf("want an error naming the 404, got %v", err)
	}

	deadline := time.Now().Add(5 * time.Second)
	for heldAcrossRoutes(client) != 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if n := heldAcrossRoutes(client); n != 0 {
		t.Fatalf("clients are still held %d times across both routes", n)
	}
}

// heldAcrossRoutes is how many holds the clients of both pools carry.
func heldAcrossRoutes(client *Client) int32 {
	client.access.Lock()
	defer client.access.Unlock()
	var total int32
	for _, route := range []*route{client.upload, client.download} {
		for _, mux := range route.mux.clients {
			total += mux.running.Load()
		}
	}
	return total
}

func TestARefusedDownloadDialIsAnErrorAndReleasesBothRoutes(t *testing.T) {
	// A download server that does not answer at all — a CDN that is down —
	// fails inside the dial, not on the first read as a 404 does.
	closed := listenTCP(t)
	port := M.SocksaddrFromNet(closed.Addr()).Port
	_ = closed.Close()
	up := startHTTP2(t, config.Options{Mode: config.ModePacketUp, Path: "/xh"})
	options := config.Options{
		Mode: config.ModePacketUp,
		Path: "/xh",
		Download: &config.Download{
			Server:     "127.0.0.1",
			ServerPort: port,
			Options:    config.Options{Path: "/xh"},
		},
	}
	client := dialClient(t, up, options)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx)
	if err == nil {
		_ = conn.Close()
		t.Fatal("a dial to a closed port succeeded")
	}
	if n := heldAcrossRoutes(client); n != 0 {
		t.Fatalf("a failed dial left %d holds across both routes", n)
	}
}

func TestRotatedUploadsStayOnTheMainRoute(t *testing.T) {
	// Every client of the main pool takes three requests, and 64 KiB in
	// 2000-byte posts is some thirty: the uploader is moved to a fresh
	// client again and again, and every one must come from the main pool.
	three := config.Range{From: 3, To: 3}
	small := config.Range{From: 2000, To: 2000}
	up, down, client := startSplit(t, serveHTTP2, serveHTTP2,
		config.Options{
			Mode:               config.ModePacketUp,
			Path:               "/xh",
			ScMaxEachPostBytes: &small,
			Xmux:               &config.Xmux{HMaxRequestTimes: &three},
		},
		config.Options{Path: "/xh"})

	roundTrip(t, dialOrFail(t, client), randomBytes(t, 64<<10))

	if gets, uploads := countMethods(down.server.recorded()); gets != 1 || uploads != 0 {
		t.Fatalf("download route saw %d GETs and %d uploads, want 1 and 0", gets, uploads)
	}
	if accepted := up.listener.accepted.Load(); accepted < 2 {
		t.Fatalf("the main route opened %d connections: the uploads never rotated", accepted)
	}
}

func TestUploadSideOptionsComeFromTheMainRoute(t *testing.T) {
	// The session id's alphabet and length, and the size of a post, are the
	// main route's; the download route, as the app writes it, has neither.
	eight := config.Range{From: 8, To: 8}
	small := config.Range{From: 2000, To: 2000}
	up, down, client := startSplit(t, serveHTTP2, serveHTTP2,
		config.Options{
			Mode:               config.ModePacketUp,
			Path:               "/xh",
			SessionIDTable:     "hex",
			SessionIDLength:    &eight,
			ScMaxEachPostBytes: &small,
		},
		config.Options{Path: "/xh"})

	roundTrip(t, dialOrFail(t, client), randomBytes(t, 32<<10))

	idShape := regexp.MustCompile(`^/xh/([0-9a-f]{8})(/|$)`)
	gets := down.server.recorded()
	if len(gets) != 1 {
		t.Fatalf("download requests: %+v", gets)
	}
	match := idShape.FindStringSubmatch(gets[0].path)
	if match == nil {
		t.Fatalf("the GET carries %q, not an id of the main route's table", gets[0].path)
	}
	for _, request := range up.server.recorded() {
		if !strings.HasPrefix(request.path, "/xh/"+match[1]+"/") {
			t.Fatalf("an upload went to %q, not session %s", request.path, match[1])
		}
		if request.bodyLen > int(small.To) {
			t.Fatalf("a post carried %d bytes, the main route allows %d", request.bodyLen, small.To)
		}
	}
}

func TestTheGETSpendsTheDownloadRoutesRequests(t *testing.T) {
	// One request per client on the download route: every GET needs a
	// fresh connection, which only holds if the GET is charged to that pool.
	one := config.Range{From: 1, To: 1}
	_, down, client := startSplit(t, serveHTTP2, serveHTTP2,
		config.Options{Mode: config.ModeStreamUp, Path: "/xh"},
		config.Options{Path: "/xh", Xmux: &config.Xmux{HMaxRequestTimes: &one}})

	for range 3 {
		roundTrip(t, dialOrFail(t, client), randomBytes(t, 4<<10))
	}

	if accepted := down.listener.accepted.Load(); accepted != 3 {
		t.Fatalf("download route: %d connections for 3 GETs, want one each", accepted)
	}
}

func TestCloseResetsBothRoutes(t *testing.T) {
	// One connection per pool: a second dial would reuse it, unless Close
	// took it away.
	one := config.Range{From: 1, To: 1}
	up, down, client := startSplit(t, serveHTTP2, serveHTTP2,
		config.Options{Mode: config.ModeStreamUp, Path: "/xh", Xmux: &config.Xmux{MaxConnections: &one}},
		config.Options{Path: "/xh", Xmux: &config.Xmux{MaxConnections: &one}})
	roundTrip(t, dialOrFail(t, client), randomBytes(t, 4<<10))

	_ = client.Close()
	roundTrip(t, dialOrFail(t, client), randomBytes(t, 4<<10))

	if accepted := down.listener.accepted.Load(); accepted != 2 {
		t.Fatalf("download route: %d connections, want a fresh one after Close", accepted)
	}
	if accepted := up.listener.accepted.Load(); accepted != 2 {
		t.Fatalf("main route: %d connections, want a fresh one after Close", accepted)
	}
}

func TestADownloadTLSBlockIsReadAsStrictlyAsSingBoxReadsItsOwn(t *testing.T) {
	up := startHTTP2(t, config.Options{Mode: config.ModePacketUp})
	options := config.Options{
		Mode: config.ModePacketUp,
		Download: &config.Download{
			Server:     "127.0.0.1",
			ServerPort: 443,
			TLS:        json.RawMessage(`{"enabled":true,"bogus":1}`),
		},
	}

	_, err := NewClient(context.Background(), N.SystemDialer, up.addr, options, up.tls)

	if err == nil || !strings.Contains(err.Error(), "download") || !strings.Contains(err.Error(), "bogus") {
		t.Fatalf("want an error naming the download route and the field, got %v", err)
	}
}

func TestAutoWithRealityAndADownloadRouteIsStreamUp(t *testing.T) {
	// REALITY cannot run hermetically; the decision can. One request cannot
	// carry two routes, so Xray picks stream-up where it would pick stream-one.
	if mode := decideMode(config.ModeAuto, true, true); mode != config.ModeStreamUp {
		t.Fatalf("auto + REALITY + download = %s, want stream-up", mode)
	}
	if mode := decideMode(config.ModeAuto, true, false); mode != config.ModeStreamOne {
		t.Fatalf("auto + REALITY = %s, want stream-one", mode)
	}
	if mode := decideMode(config.ModeAuto, false, true); mode != config.ModePacketUp {
		t.Fatalf("auto + download = %s, want packet-up", mode)
	}
}

func TestEveryDownloadTLSTheAppWritesIsOneSingBoxBuilds(t *testing.T) {
	// The fixture is what the app's builder emits (see config/contract_test.go);
	// config cannot import sing-box, so the `tls` of each download route is
	// held to sing-box's own decoder and constructor here.
	raw, err := os.ReadFile("config/testdata/dart_blocks.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Cases []struct {
			Name      string `json:"name"`
			Transport struct {
				Download *config.Download `json:"download"`
			} `json:"transport"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	seen := 0
	for _, c := range fixture.Cases {
		download := c.Transport.Download
		if download == nil || len(download.TLS) == 0 {
			continue
		}
		seen++
		resolved := &config.ResolvedDownload{Server: download.Server, ServerPort: download.ServerPort, TLS: download.TLS}
		tlsConfig, err := newDownloadTLS(context.Background(), resolved)
		if err != nil && strings.Contains(err.Error(), "not included in this build") {
			// uTLS and REALITY come with the core's build tags; CI runs this
			// package with them too (the overlay step in core.yml).
			t.Logf("%s: needs the core's build tags: %v", c.Name, err)
			continue
		}
		if err != nil {
			t.Errorf("%s: sing-box refuses the download route's tls: %v", c.Name, err)
		} else if tlsConfig == nil {
			t.Errorf("%s: a tls block built no TLS", c.Name)
		}
	}
	if seen == 0 {
		t.Fatal("the fixture has no download route with TLS")
	}
}
