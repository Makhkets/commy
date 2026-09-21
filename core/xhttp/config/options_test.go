package config

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestRangeReadsWhatXrayReads(t *testing.T) {
	cases := map[string]Range{
		`5`:          {From: 5, To: 5},
		`"5"`:        {From: 5, To: 5},
		`"100-1000"`: {From: 100, To: 1000},
		`"1000-100"`: {From: 100, To: 1000},
		`" 16 - 32"`: {From: 16, To: 32},
		`""`:         {},
		`0`:          {},
		`"-1"`:       {From: -1, To: -1},
	}
	for input, want := range cases {
		var got Range
		if err := json.Unmarshal([]byte(input), &got); err != nil {
			t.Errorf("%s: %v", input, err)
			continue
		}
		if got != want {
			t.Errorf("%s: got %+v, want %+v", input, got, want)
		}
	}
	for _, input := range []string{`"a-b"`, `"1-"`, `true`, `{}`, `"1-2-3x"`} {
		var got Range
		if err := json.Unmarshal([]byte(input), &got); err == nil {
			t.Errorf("%s: accepted as %+v", input, got)
		}
	}
}

func TestRangeSurvivesARoundTrip(t *testing.T) {
	for _, value := range []Range{{From: 3, To: 3}, {From: 100, To: 1000}} {
		encoded, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		var decoded Range
		if err := json.Unmarshal(encoded, &decoded); err != nil {
			t.Fatal(err)
		}
		if decoded != value {
			t.Fatalf("%+v became %s became %+v", value, encoded, decoded)
		}
	}
}

func TestPickStaysInsideTheRange(t *testing.T) {
	value := Range{From: 100, To: 110}
	seen := map[int32]bool{}
	for range 2000 {
		picked := value.Pick()
		if picked < value.From || picked > value.To {
			t.Fatalf("picked %d from %v", picked, value)
		}
		seen[picked] = true
	}
	if len(seen) != 11 {
		t.Fatalf("2000 draws hit %d of 11 values: both ends must be reachable", len(seen))
	}
	if got := (Range{From: 7, To: 7}).Pick(); got != 7 {
		t.Fatalf("a fixed range picked %d", got)
	}
}

func TestDefaultsAreXrays(t *testing.T) {
	resolved, err := Options{}.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	checks := map[string]bool{
		"mode auto":                 resolved.Mode == ModeAuto,
		"padding 100-1000":          resolved.XPaddingBytes == Range{From: 100, To: 1000},
		"post size 1000000":         resolved.ScMaxEachPostBytes == Range{From: 1000000, To: 1000000},
		"post interval 30":          resolved.ScMinPostsIntervalMs == Range{From: 30, To: 30},
		"uplink POST":               resolved.UplinkHTTPMethod == "POST",
		"session in path":           resolved.SessionPlacement == PlacementPath,
		"seq in path":               resolved.SeqPlacement == PlacementPath,
		"upload placement auto":     resolved.UplinkDataPlacement == PlacementAuto,
		"upload key X-Data":         resolved.UplinkDataKey == "X-Data",
		"padding key":               resolved.XPaddingKey == "x_padding",
		"padding header":            resolved.XPaddingHeader == "X-Padding",
		"padding in Referer query":  resolved.XPaddingPlacement == PlacementQueryInHeader,
		"padding repeat-x":          resolved.XPaddingMethod == PaddingRepeatX,
		"xmux 3 connections":        resolved.MaxConnections == Range{From: 3, To: 3},
		"xmux no concurrency limit": resolved.MaxConcurrency.IsZero(),
		"xmux 600-900 requests":     resolved.HMaxRequestTimes == Range{From: 600, To: 900},
		"xmux 1800-3000 seconds":    resolved.HMaxReusableSecs == Range{From: 1800, To: 3000},
	}
	for name, ok := range checks {
		if !ok {
			t.Errorf("default is not Xray's: %s", name)
		}
	}
}

func TestAnXmuxBlockReplacesTheDefaultsWholesale(t *testing.T) {
	resolved, err := Options{Xmux: &Xmux{MaxConcurrency: &Range{From: 16, To: 32}}}.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	if !resolved.MaxConnections.IsZero() || !resolved.HMaxRequestTimes.IsZero() {
		t.Fatalf("a set xmux block must not inherit the defaults: %+v", resolved)
	}
	// An empty block is no block.
	resolved, err = Options{Xmux: &Xmux{}}.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	if resolved.MaxConnections != (Range{From: 3, To: 3}) {
		t.Fatal("an empty xmux block should mean the defaults")
	}
}

func TestWhatXrayRefusesIsRefused(t *testing.T) {
	r := func(from, to int32) *Range { return &Range{From: from, To: to} }
	cases := map[string]Options{
		"unknown mode":                    {Mode: "stream-down"},
		"host in headers":                 {Headers: map[string]string{"HoSt": "a"}},
		"padding switched off":            {XPaddingBytes: r(0, 100)},
		"padding placement":               {XPaddingPlacement: "body"},
		"padding method":                  {XPaddingMethod: "random"},
		"uplink placement":                {UplinkDataPlacement: "query"},
		"header upload outside packet-up": {Mode: ModeStreamUp, UplinkDataPlacement: PlacementHeader},
		"header upload in auto":           {UplinkDataPlacement: PlacementHeader},
		"GET upload outside packet-up":    {Mode: ModeStreamOne, UplinkHTTPMethod: "get"},
		"session placement":               {SessionPlacement: "body"},
		"seq placement":                   {SeqPlacement: "body"},
		"session alphabet too small":      {SessionIDTable: "number", SessionIDLength: r(2, 3)},
		"session alphabet without length": {SessionIDTable: "hex"},
		"session alphabet not ASCII":      {SessionIDTable: "абвгдежзийклмнопрст", SessionIDLength: r(20, 20)},
		"session id absurdly long":        {SessionIDTable: "hex", SessionIDLength: r(16, 2000000000)},
		"post size zero":                  {ScMaxEachPostBytes: r(0, 100)},
		"both xmux limits":                {Xmux: &Xmux{MaxConnections: r(2, 2), MaxConcurrency: r(4, 4)}},
	}
	for name, options := range cases {
		if _, err := options.Resolve(); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}

func TestPathNormalisation(t *testing.T) {
	cases := []struct {
		options Options
		path    string
		query   string
	}{
		{Options{}, "/", ""},
		{Options{Path: "xhttp"}, "/xhttp/", ""},
		{Options{Path: "/xhttp/"}, "/xhttp/", ""},
		{Options{Path: "/a/b?ed=2048&x=1"}, "/a/b/", "ed=2048&x=1"},
		// Nothing rides in the path, and the slash is still there: a released
		// Xray server (v26.3.27) answers 404 without it.
		{Options{Path: "/exact", SessionPlacement: "header", SeqPlacement: "query"}, "/exact/", ""},
	}
	for _, c := range cases {
		resolved, err := c.options.Resolve()
		if err != nil {
			t.Fatal(err)
		}
		if got := resolved.NormalizedPath(); got != c.path {
			t.Errorf("path %q: got %q, want %q", c.options.Path, got, c.path)
		}
		if got := resolved.NormalizedQuery(); got != c.query {
			t.Errorf("query of %q: got %q, want %q", c.options.Path, got, c.query)
		}
	}
}

func TestTheBlockDecodesFromTheJSONWeEmit(t *testing.T) {
	document := `{
		"mode": "packet-up",
		"host": "cdn.example",
		"path": "/x",
		"headers": {"X-Forwarded-Proto": "https"},
		"x_padding_bytes": "200-400",
		"no_grpc_header": true,
		"sc_max_each_post_bytes": 500000,
		"sc_min_posts_interval_ms": "10-50",
		"xmux": {"max_concurrency": "16-32", "h_max_request_times": "600-900", "h_keep_alive_period": 30},
		"x_padding_obfs_mode": true,
		"x_padding_placement": "cookie",
		"uplink_http_method": "PUT",
		"session_placement": "header",
		"seq_placement": "query",
		"uplink_data_placement": "body",
		"session_id_table": "base36",
		"session_id_length": "16-24"
	}`
	var options Options
	decoder := json.NewDecoder(strings.NewReader(document))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&options); err != nil {
		t.Fatal(err)
	}
	resolved, err := options.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	if resolved.XPaddingBytes != (Range{From: 200, To: 400}) ||
		resolved.ScMaxEachPostBytes != (Range{From: 500000, To: 500000}) ||
		resolved.MaxConcurrency != (Range{From: 16, To: 32}) ||
		resolved.HKeepAlivePeriod != 30 ||
		resolved.UplinkHTTPMethod != "PUT" ||
		resolved.SessionKey != "X-Session" || resolved.SeqKey != "x_seq" {
		t.Fatalf("decoded wrong: %+v", resolved)
	}
	// And back: what we read is what we would write.
	encoded, err := json.Marshal(options)
	if err != nil {
		t.Fatal(err)
	}
	var again Options
	if err := json.Unmarshal(encoded, &again); err != nil {
		t.Fatal(err)
	}
	second, err := again.Resolve()
	if err != nil {
		t.Fatal(err)
	}
	if second.XPaddingBytes != resolved.XPaddingBytes || second.MaxConcurrency != resolved.MaxConcurrency {
		t.Fatal("the block does not survive a round trip through JSON")
	}
}
