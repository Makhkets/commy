package xhttp

import (
	crand "crypto/rand"
	"encoding/binary"
	"math"
	"math/rand/v2"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// A request that says nothing about its client is itself a signature: Go's
// default User-Agent on a path that otherwise looks like a web app is the
// easiest XHTTP tell there is. So, like Xray, every request is dressed as a
// browser `fetch()` unless the configuration names its own User-Agent.
//
// Setting User-Agent to one of the bare words below picks that browser's
// header set; any other value is sent as is, with nothing added around it.
const (
	browserChrome  = "chrome"
	browserFirefox = "firefox"
	browserSafari  = "safari"
	browserEdge    = "edge"
	browserCurl    = "curl"
	browserGolang  = "golang"
)

// requestHeader builds the headers every XHTTP request starts from.
func requestHeader(custom map[string]string) http.Header {
	header := http.Header{}
	for key, value := range custom {
		header.Add(key, value)
	}
	if len(header.Values("User-Agent")) == 0 {
		applyBrowserHeaders(header, browserChrome)
		return header
	}
	switch name := header.Get("User-Agent"); name {
	case browserChrome, browserFirefox, browserSafari, browserEdge, browserCurl, browserGolang:
		applyBrowserHeaders(header, name)
	}
	return header
}

func applyBrowserHeaders(header http.Header, browser string) {
	profile := browserProfile()
	switch browser {
	case browserChrome:
		// Set by key, not through Set: these names are not in canonical form
		// and a browser does not send them in canonical form either.
		header["Sec-CH-UA"] = []string{profile.chromeBrands}
		header["Sec-CH-UA-Mobile"] = []string{"?0"}
		header["Sec-CH-UA-Platform"] = []string{`"Windows"`}
		header["DNT"] = []string{"1"}
		header.Set("User-Agent", profile.chromeUA)
		header.Set("Accept-Language", "en-US,en;q=0.9")
	case browserEdge:
		header["Sec-CH-UA"] = []string{profile.edgeBrands}
		header["Sec-CH-UA-Mobile"] = []string{"?0"}
		header["Sec-CH-UA-Platform"] = []string{`"Windows"`}
		header["DNT"] = []string{"1"}
		header.Set("User-Agent", profile.edgeUA)
		header.Set("Accept-Language", "en-US,en;q=0.9")
	case browserFirefox:
		header.Set("User-Agent", profile.firefoxUA)
		header["DNT"] = []string{"1"}
		header.Set("Accept-Language", "en-US,en;q=0.5")
	case browserSafari:
		header.Set("User-Agent", profile.safariUA)
		header.Set("Accept-Language", "en-US,en;q=0.9")
	case browserGolang:
		// Asked for by name: let net/http put its own User-Agent.
		header.Del("User-Agent")
		return
	case browserCurl:
		header.Set("User-Agent", profile.curlUA)
		return
	}

	// What a browser adds to a same-origin fetch().
	header.Set("Sec-Fetch-Mode", "cors")
	header.Set("Sec-Fetch-Dest", "empty")
	header.Set("Sec-Fetch-Site", "same-origin")
	if header.Get("Priority") == "" {
		switch browser {
		case browserChrome, browserEdge:
			header.Set("Priority", "u=1, i")
		case browserFirefox:
			header.Set("Priority", "u=4")
		case browserSafari:
			header.Set("Priority", "u=3, i")
		}
	}
	if header.Get("Cache-Control") == "" {
		header.Set("Cache-Control", "no-cache")
	}
	if header.Get("Pragma") == "" {
		header.Set("Pragma", "no-cache")
	}
	if header.Get("Accept") == "" {
		header.Set("Accept", "*/*")
	}
}

type browserStrings struct {
	chromeUA     string
	chromeBrands string
	edgeUA       string
	edgeBrands   string
	firefoxUA    string
	safariUA     string
	curlUA       string
}

// browserProfile is computed once per process.
//
// The versions track the calendar, because a client that announces the same
// Chrome for two years is as recognisable as one that announces none. They are
// held for the life of the process, because a browser does not change version
// between two requests either.
var browserProfile = sync.OnceValue(func() browserStrings {
	return newBrowserStrings(time.Now(), newSeededRand())
})

func newSeededRand() *rand.Rand {
	var seed [16]byte
	if _, err := crand.Read(seed[:]); err != nil {
		binary.LittleEndian.PutUint64(seed[:8], uint64(time.Now().UnixNano()))
	}
	return rand.New(rand.NewPCG(
		binary.LittleEndian.Uint64(seed[:8]),
		binary.LittleEndian.Uint64(seed[8:]),
	))
}

func newBrowserStrings(now time.Time, rng *rand.Rand) browserStrings {
	chrome := chromeVersion(now, rng)
	chromeText := strconv.Itoa(chrome)
	firefox := strconv.Itoa(firefoxVersion(now, rng))
	chromeUA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
		"(KHTML, like Gecko) Chrome/" + chromeText + ".0.0.0 Safari/537.36"
	return browserStrings{
		chromeUA:     chromeUA,
		chromeBrands: greasedBrands(chrome, "Google Chrome"),
		edgeUA:       chromeUA + " Edg/" + chromeText + ".0.0.0",
		edgeBrands:   greasedBrands(chrome, "Microsoft Edge"),
		firefoxUA: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:" + firefox +
			".0) Gecko/20100101 Firefox/" + firefox + ".0",
		safariUA: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
			"(KHTML, like Gecko) Version/" + safariVersion(now, rng) + " Safari/605.1.15",
		curlUA: "curl/" + curlVersion(now, rng),
	}
}

func days(t time.Time) int64 { return t.Unix() / 86400 }

// lag draws how many days behind the newest release this "install" is: most
// users are nearly current, a few are far behind. Squaring (or cubing) a
// uniform value gives that shape.
func lag(rng *rand.Rand, power float64, span float64) int64 {
	return int64(math.Floor(math.Pow(rng.Float64(), power) * span))
}

// chromeVersion: Chrome 144 shipped on 2026-01-13, a major every ~35 days.
func chromeVersion(now time.Time, rng *rand.Rand) int {
	start := days(time.Date(2026, 1, 13, 0, 0, 0, 0, time.UTC))
	behind := days(now) - start - 35 - lag(rng, 2, 105)
	return max(144, 144+int(behind/35))
}

// firefoxVersion: Firefox 128 shipped in July 2024, a major every ~30 days.
func firefoxVersion(now time.Time, rng *rand.Rand) int {
	start := days(time.Date(2024, 7, 29, 0, 0, 0, 0, time.UTC))
	behind := days(now) - start - 25 - lag(rng, 2, 50)
	return max(128, 128+int(behind/30))
}

// curlVersion: curl 8.0.0 shipped on 2023-03-20, a minor every ~57 days.
func curlVersion(now time.Time, rng *rand.Rand) string {
	start := days(time.Date(2023, 3, 20, 0, 0, 0, 0, time.UTC))
	behind := days(now) - start - 60 - lag(rng, 2, 165)
	return "8." + strconv.Itoa(max(0, int(behind/57))) + ".0"
}

var safariMinors = [25]int{
	0, 0, 0, 1, 1,
	1, 2, 2, 2, 2, 3, 3, 3, 4, 4,
	4, 5, 5, 5, 5, 5, 6, 6, 6, 6,
}

// safariVersion: a major each September, numbered after the year, and a minor
// that creeps up over the twelve months that follow.
func safariVersion(now time.Time, rng *rand.Rand) string {
	year := now.Year()
	delay := int(lag(rng, 3, 75))
	release := time.Date(year, 9, 23, 0, 0, 0, 0, time.UTC).AddDate(0, 0, delay)
	if now.Before(release) {
		year--
		release = time.Date(year, 9, 23, 0, 0, 0, 0, time.UTC).AddDate(0, 0, delay)
	}
	slot := (now.Unix() - release.Unix()) / 1296000
	slot = min(max(slot, 0), int64(len(safariMinors)-1))
	return strconv.Itoa(year-1999) + "." + strconv.Itoa(safariMinors[slot])
}

// Chromium sends its brand list in an order and with a decoy brand that both
// depend on the major version, so that servers cannot hard-code the string.
var (
	greaseChars    = []string{" ", "(", ":", "-", ".", "/", ")", ";", "=", "?", "_"}
	greaseVersions = []string{"8", "99", "24"}
	greaseOrders   = [][3]int{{0, 1, 2}, {0, 2, 1}, {1, 0, 2}, {1, 2, 0}, {2, 0, 1}, {2, 1, 0}}
)

func greasedBrands(major int, brand string) string {
	version := strconv.Itoa(major)
	brands := [3]string{
		`"Not` + greaseChars[major%len(greaseChars)] + "A" +
			greaseChars[(major+1)%len(greaseChars)] + `Brand";v="` +
			greaseVersions[major%len(greaseVersions)] + `"`,
		`"Chromium";v="` + version + `"`,
		`"` + brand + `";v="` + version + `"`,
	}
	order := greaseOrders[major%len(greaseOrders)]
	shuffled := make([]string, len(brands))
	for from, to := range order {
		shuffled[to] = brands[from]
	}
	return strings.Join(shuffled, ", ")
}
