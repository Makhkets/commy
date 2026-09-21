// Package config holds the options of the XHTTP client transport.
//
// It is a package of its own, and imports nothing from sing-box, on purpose.
// The sing-box `option` package has to import these types (through the build
// overlay in core/overlay), while the transport in the parent package imports
// sing-box. One package doing both would be an import cycle.
//
// The JSON keys follow the spelling the rest of a sing-box document uses
// (snake_case). The meaning of every field, its default and the rules that tie
// fields together are Xray's: the server on the other end is Xray, so its
// reading of a value is the only one that matters. They were read off
// infra/conf/transport_method.go and transport/internet/splithttp at Xray
// v26.9.9, not recalled.
package config

import (
	"errors"
	"math/big"
	"strings"
)

// TransportType is the value of `type` in a transport block that selects
// XHTTP. sing-box has constants for its own transports; this one lives here
// because both packages the overlay touches need it.
const TransportType = "xhttp"

// Modes of the transport. See the package documentation of xhttp for what
// each one puts on the wire.
const (
	ModeAuto      = "auto"
	ModePacketUp  = "packet-up"
	ModeStreamUp  = "stream-up"
	ModeStreamOne = "stream-one"
)

// Places a value can ride in a request.
const (
	PlacementQueryInHeader = "queryInHeader"
	PlacementCookie        = "cookie"
	PlacementHeader        = "header"
	PlacementQuery         = "query"
	PlacementPath          = "path"
	PlacementBody          = "body"
	PlacementAuto          = "auto"
)

// Padding generators.
const (
	PaddingRepeatX  = "repeat-x"
	PaddingTokenish = "tokenish"
)

// Options is the `transport` block of an outbound whose type is "xhttp".
//
// Only what a client reads is here. Server-side knobs of the same Xray block
// (noSSEHeader, scMaxBufferedPosts, scStreamUpServerSecs, serverMaxHeaderBytes)
// have no field: the core decodes with unknown fields disallowed, so a field
// that would silently do nothing is better refused at the door.
type Options struct {
	Mode    string            `json:"mode,omitempty"`
	Host    string            `json:"host,omitempty"`
	Path    string            `json:"path,omitempty"`
	Headers map[string]string `json:"headers,omitempty"`

	XPaddingBytes        *Range `json:"x_padding_bytes,omitempty"`
	NoGRPCHeader         bool   `json:"no_grpc_header,omitempty"`
	ScMaxEachPostBytes   *Range `json:"sc_max_each_post_bytes,omitempty"`
	ScMinPostsIntervalMs *Range `json:"sc_min_posts_interval_ms,omitempty"`
	Xmux                 *Xmux  `json:"xmux,omitempty"`

	XPaddingObfsMode  bool   `json:"x_padding_obfs_mode,omitempty"`
	XPaddingKey       string `json:"x_padding_key,omitempty"`
	XPaddingHeader    string `json:"x_padding_header,omitempty"`
	XPaddingPlacement string `json:"x_padding_placement,omitempty"`
	XPaddingMethod    string `json:"x_padding_method,omitempty"`

	UplinkHTTPMethod    string `json:"uplink_http_method,omitempty"`
	SessionPlacement    string `json:"session_placement,omitempty"`
	SessionKey          string `json:"session_key,omitempty"`
	SeqPlacement        string `json:"seq_placement,omitempty"`
	SeqKey              string `json:"seq_key,omitempty"`
	UplinkDataPlacement string `json:"uplink_data_placement,omitempty"`
	UplinkDataKey       string `json:"uplink_data_key,omitempty"`
	UplinkChunkSize     *Range `json:"uplink_chunk_size,omitempty"`
	SessionIDTable      string `json:"session_id_table,omitempty"`
	SessionIDLength     *Range `json:"session_id_length,omitempty"`
}

// Xmux decides how many HTTP connections carry the tunnel's streams and when
// one of them is retired. A zero field means "no limit".
type Xmux struct {
	MaxConcurrency   *Range `json:"max_concurrency,omitempty"`
	MaxConnections   *Range `json:"max_connections,omitempty"`
	CMaxReuseTimes   *Range `json:"c_max_reuse_times,omitempty"`
	HMaxRequestTimes *Range `json:"h_max_request_times,omitempty"`
	HMaxReusableSecs *Range `json:"h_max_reusable_secs,omitempty"`
	// HKeepAlivePeriod is in seconds. Zero picks the default of the HTTP
	// version in use, a negative value switches keep-alive pings off.
	HKeepAlivePeriod int64 `json:"h_keep_alive_period,omitempty"`
}

// IsZero reports whether nothing in the block was set.
func (x *Xmux) IsZero() bool {
	if x == nil {
		return true
	}
	return rangeOf(x.MaxConcurrency).IsZero() &&
		rangeOf(x.MaxConnections).IsZero() &&
		rangeOf(x.CMaxReuseTimes).IsZero() &&
		rangeOf(x.HMaxRequestTimes).IsZero() &&
		rangeOf(x.HMaxReusableSecs).IsZero() &&
		x.HKeepAlivePeriod == 0
}

// MaxSessionIDLength bounds a generated session id, in characters.
const MaxSessionIDLength = 256

// PredefinedTables are the alphabets a session id can be drawn from by name.
var PredefinedTables = map[string]string{
	"ALPHABET": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
	"Alphabet": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
	"BASE36":   "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
	"Base62":   "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
	"HEX":      "0123456789ABCDEF",
	"alphabet": "abcdefghijklmnopqrstuvwxyz",
	"base36":   "0123456789abcdefghijklmnopqrstuvwxyz",
	"hex":      "0123456789abcdef",
	"number":   "0123456789",
}

// Resolved is Options with every default filled in and every rule checked.
//
// The transport works from this and never from Options, so "is this field
// set" is asked in exactly one place.
type Resolved struct {
	Mode    string
	Host    string
	Path    string
	Headers map[string]string

	XPaddingBytes        Range
	NoGRPCHeader         bool
	ScMaxEachPostBytes   Range
	ScMinPostsIntervalMs Range

	MaxConcurrency   Range
	MaxConnections   Range
	CMaxReuseTimes   Range
	HMaxRequestTimes Range
	HMaxReusableSecs Range
	HKeepAlivePeriod int64

	XPaddingObfsMode  bool
	XPaddingKey       string
	XPaddingHeader    string
	XPaddingPlacement string
	XPaddingMethod    string

	UplinkHTTPMethod    string
	SessionPlacement    string
	SessionKey          string
	SeqPlacement        string
	SeqKey              string
	UplinkDataPlacement string
	UplinkDataKey       string
	UplinkChunkSize     Range
	SessionIDTable      string
	SessionIDLength     Range
}

// Resolve fills the defaults and checks the rules Xray checks.
//
// An option the server would refuse is refused here, when the outbound is
// created, rather than as a 400 the user has to find in a log.
func (o Options) Resolve() (Resolved, error) {
	r := Resolved{
		Mode:                 o.Mode,
		Host:                 o.Host,
		Path:                 o.Path,
		Headers:              o.Headers,
		XPaddingBytes:        rangeOf(o.XPaddingBytes),
		NoGRPCHeader:         o.NoGRPCHeader,
		ScMaxEachPostBytes:   rangeOf(o.ScMaxEachPostBytes),
		ScMinPostsIntervalMs: rangeOf(o.ScMinPostsIntervalMs),
		XPaddingObfsMode:     o.XPaddingObfsMode,
		XPaddingKey:          o.XPaddingKey,
		XPaddingHeader:       o.XPaddingHeader,
		XPaddingPlacement:    o.XPaddingPlacement,
		XPaddingMethod:       o.XPaddingMethod,
		UplinkHTTPMethod:     strings.ToUpper(o.UplinkHTTPMethod),
		SessionPlacement:     o.SessionPlacement,
		SessionKey:           o.SessionKey,
		SeqPlacement:         o.SeqPlacement,
		SeqKey:               o.SeqKey,
		UplinkDataPlacement:  o.UplinkDataPlacement,
		UplinkDataKey:        o.UplinkDataKey,
		UplinkChunkSize:      rangeOf(o.UplinkChunkSize),
		SessionIDTable:       o.SessionIDTable,
		SessionIDLength:      rangeOf(o.SessionIDLength),
	}

	switch r.Mode {
	case "":
		r.Mode = ModeAuto
	case ModeAuto, ModePacketUp, ModeStreamUp, ModeStreamOne:
	default:
		return Resolved{}, errors.New("unsupported mode: " + r.Mode)
	}

	// The Host header has one owner: `host`, then the TLS server name, then the
	// address. A second copy in `headers` would be a request with two.
	for key := range r.Headers {
		if strings.EqualFold(key, "host") {
			return Resolved{}, errors.New(`"headers" can't contain "host"`)
		}
	}

	if !r.XPaddingBytes.IsZero() && (r.XPaddingBytes.From <= 0 || r.XPaddingBytes.To <= 0) {
		return Resolved{}, errors.New("x_padding_bytes cannot be disabled")
	}
	if r.XPaddingBytes.To == 0 {
		r.XPaddingBytes = Range{From: 100, To: 1000}
	}

	if r.XPaddingKey == "" {
		r.XPaddingKey = "x_padding"
	}
	if r.XPaddingHeader == "" {
		r.XPaddingHeader = "X-Padding"
	}
	switch r.XPaddingPlacement {
	case "":
		r.XPaddingPlacement = PlacementQueryInHeader
	case PlacementCookie, PlacementHeader, PlacementQuery, PlacementQueryInHeader:
	default:
		return Resolved{}, errors.New("unsupported padding placement: " + r.XPaddingPlacement)
	}
	switch r.XPaddingMethod {
	case "":
		r.XPaddingMethod = PaddingRepeatX
	case PaddingRepeatX, PaddingTokenish:
	default:
		return Resolved{}, errors.New("unsupported padding method: " + r.XPaddingMethod)
	}

	switch r.UplinkDataPlacement {
	case "":
		r.UplinkDataPlacement = PlacementAuto
	case PlacementAuto, PlacementBody:
	case PlacementCookie, PlacementHeader:
		if r.Mode != ModePacketUp {
			return Resolved{}, errors.New(
				"uplink_data_placement can be " + r.UplinkDataPlacement + " only in packet-up mode")
		}
	default:
		return Resolved{}, errors.New("unsupported uplink data placement: " + r.UplinkDataPlacement)
	}

	if r.UplinkHTTPMethod == "" {
		r.UplinkHTTPMethod = "POST"
	}
	if r.UplinkHTTPMethod == "GET" && r.Mode != ModePacketUp {
		return Resolved{}, errors.New("uplink_http_method can be GET only in packet-up mode")
	}

	switch r.SessionPlacement {
	case "":
		r.SessionPlacement = PlacementPath
	case PlacementPath, PlacementCookie, PlacementHeader, PlacementQuery:
	default:
		return Resolved{}, errors.New("unsupported session placement: " + r.SessionPlacement)
	}
	switch r.SeqPlacement {
	case "":
		r.SeqPlacement = PlacementPath
	case PlacementPath, PlacementCookie, PlacementHeader, PlacementQuery:
	default:
		return Resolved{}, errors.New("unsupported seq placement: " + r.SeqPlacement)
	}
	if r.SessionKey == "" {
		r.SessionKey = defaultKey(r.SessionPlacement, "x_session", "X-Session")
	}
	if r.SeqKey == "" {
		r.SeqKey = defaultKey(r.SeqPlacement, "x_seq", "X-Seq")
	}

	if r.SessionIDTable != "" {
		if predefined, ok := PredefinedTables[r.SessionIDTable]; ok {
			r.SessionIDTable = predefined
		}
		if r.SessionIDLength.From <= 0 {
			return Resolved{}, errors.New("session_id_length must be greater than 0")
		}
		// Xray has no upper bound. The id rides in a URL or a header, so nothing
		// longer than this survives a real server anyway — and without a bound
		// a subscription could make the core count to two billion at start.
		if r.SessionIDLength.To > MaxSessionIDLength {
			return Resolved{}, errors.New("session_id_length is too large")
		}
		for i := 0; i < len(r.SessionIDTable); i++ {
			if r.SessionIDTable[i] >= 0x80 {
				return Resolved{}, errors.New("session_id_table must contain only ASCII characters")
			}
		}
		// Two live sessions with one id are one session to the server, and it
		// would splice their uploads together. 2^31 ids keeps that a non-event.
		room := roomSize(len(r.SessionIDTable), r.SessionIDLength.From, r.SessionIDLength.To)
		if room.Cmp(big.NewInt(2<<30)) < 0 {
			return Resolved{}, errors.New("session_id_table or session_id_length is too small")
		}
	}

	if r.UplinkDataPlacement != PlacementBody && r.UplinkDataKey == "" {
		switch r.UplinkDataPlacement {
		case PlacementCookie:
			r.UplinkDataKey = "x_data"
		case PlacementAuto, PlacementHeader:
			r.UplinkDataKey = "X-Data"
		}
	}

	if r.ScMaxEachPostBytes.To == 0 {
		r.ScMaxEachPostBytes = Range{From: 1000000, To: 1000000}
	}
	if r.ScMaxEachPostBytes.From <= 0 {
		return Resolved{}, errors.New("sc_max_each_post_bytes should be bigger than 0")
	}
	if r.ScMinPostsIntervalMs.To == 0 {
		r.ScMinPostsIntervalMs = Range{From: 30, To: 30}
	}
	if r.ScMinPostsIntervalMs.From < 0 {
		return Resolved{}, errors.New("sc_min_posts_interval_ms cannot be negative")
	}

	switch {
	case r.UplinkChunkSize.To == 0:
		switch r.UplinkDataPlacement {
		case PlacementCookie:
			r.UplinkChunkSize = Range{From: 2 * 1024, To: 3 * 1024}
		case PlacementHeader:
			r.UplinkChunkSize = Range{From: 3 * 1000, To: 4 * 1000}
		default:
			r.UplinkChunkSize = r.ScMaxEachPostBytes
		}
	case r.UplinkChunkSize.From < 64:
		r.UplinkChunkSize = Range{From: 64, To: max(64, r.UplinkChunkSize.To)}
	}

	if o.Xmux.IsZero() {
		r.MaxConnections = Range{From: 3, To: 3}
		r.HMaxRequestTimes = Range{From: 600, To: 900}
		r.HMaxReusableSecs = Range{From: 1800, To: 3000}
	} else {
		r.MaxConcurrency = rangeOf(o.Xmux.MaxConcurrency)
		r.MaxConnections = rangeOf(o.Xmux.MaxConnections)
		r.CMaxReuseTimes = rangeOf(o.Xmux.CMaxReuseTimes)
		r.HMaxRequestTimes = rangeOf(o.Xmux.HMaxRequestTimes)
		r.HMaxReusableSecs = rangeOf(o.Xmux.HMaxReusableSecs)
		r.HKeepAlivePeriod = o.Xmux.HKeepAlivePeriod
		if r.MaxConnections.To > 0 && r.MaxConcurrency.To > 0 {
			return Resolved{}, errors.New("max_connections cannot be specified together with max_concurrency")
		}
	}

	return r, nil
}

// NormalizedPath is the path part of `path`, always starting and ending with
// a slash.
//
// Xray changed its mind about the trailing slash. Up to and including v26.3.27
// both sides add it always, and the server answers 404 to a request without
// it. Later versions add it only when the session id or the sequence number
// rides in the path — and their server matches by prefix, so it takes the
// slash too. Always adding it is the one spelling every server accepts; it was
// found by running against a released Xray, not by reading the newest source.
func (r Resolved) NormalizedPath() string {
	path, _, _ := strings.Cut(r.Path, "?")
	if path == "" || path[0] != '/' {
		path = "/" + path
	}
	if path[len(path)-1] != '/' {
		path += "/"
	}
	return path
}

// NormalizedQuery is whatever followed the question mark in `path`.
func (r Resolved) NormalizedQuery() string {
	_, query, _ := strings.Cut(r.Path, "?")
	return query
}

func rangeOf(r *Range) Range {
	if r == nil {
		return Range{}
	}
	return *r
}

func defaultKey(placement, lower, header string) string {
	switch placement {
	case PlacementHeader:
		return header
	case PlacementCookie, PlacementQuery:
		return lower
	default:
		return ""
	}
}

// roomSize counts the distinct ids a table of [tableLen] characters yields
// across every length from [from] to [to].
func roomSize(tableLen int, from, to int32) *big.Int {
	total := new(big.Int)
	base := big.NewInt(int64(tableLen))
	for length := from; length <= to; length++ {
		total.Add(total, new(big.Int).Exp(base, big.NewInt(int64(length)), nil))
	}
	return total
}
