package xhttp

import (
	"bytes"
	crand "crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"io"
	"math/rand/v2"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/Makhkets/commy/core/xhttp/config"
)

// fillStreamRequest dresses a long-lived request: the download GET, or the
// POST that streams the upload.
func fillStreamRequest(request *http.Request, options *config.Resolved, sessionID string) {
	request.Header = requestHeader(options.Headers)
	applyPadding(request, options)
	applyMeta(request, options, sessionID, "")
	if request.Body != nil && !options.NoGRPCHeader {
		// A reverse proxy that sees gRPC leaves the stream alone instead of
		// buffering the request until it ends — which, here, is never.
		request.Header.Set("Content-Type", "application/grpc")
	}
}

// fillPacketRequest dresses one packet-up upload and attaches [payload].
func fillPacketRequest(
	request *http.Request,
	options *config.Resolved,
	sessionID string,
	seq string,
	payload []byte,
) {
	request.Header = requestHeader(options.Headers)
	switch options.UplinkDataPlacement {
	case config.PlacementHeader:
		writeChunks(payload, options, func(index int, chunk string) {
			request.Header.Set(options.UplinkDataKey+"-"+strconv.Itoa(index), chunk)
		})
	case config.PlacementCookie:
		writeChunks(payload, options, func(index int, chunk string) {
			request.AddCookie(&http.Cookie{
				Name:  options.UplinkDataKey + "_" + strconv.Itoa(index),
				Value: chunk,
			})
		})
	default:
		request.Body = io.NopCloser(bytes.NewReader(payload))
		request.ContentLength = int64(len(payload))
		// Lets the HTTP client replay the body when it retries on a fresh
		// connection; without it a retry would send an empty upload.
		request.GetBody = func() (io.ReadCloser, error) {
			return io.NopCloser(bytes.NewReader(payload)), nil
		}
	}
	applyPadding(request, options)
	applyMeta(request, options, sessionID, seq)
}

// writeChunks cuts [payload], base64-encoded, into pieces a header or a cookie
// can hold, and hands each to [put] with its index.
func writeChunks(payload []byte, options *config.Resolved, put func(index int, chunk string)) {
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	for index := 0; len(encoded) > 0; index++ {
		size := min(max(int(options.UplinkChunkSize.Pick()), 1), len(encoded))
		put(index, encoded[:size])
		encoded = encoded[size:]
	}
}

// applyMeta writes the session id and the sequence number where the server
// was told to look for them.
func applyMeta(request *http.Request, options *config.Resolved, sessionID, seq string) {
	if sessionID != "" {
		placeValue(request, options.SessionPlacement, options.SessionKey, sessionID)
	}
	if seq != "" {
		placeValue(request, options.SeqPlacement, options.SeqKey, seq)
	}
}

func placeValue(request *http.Request, placement, key, value string) {
	switch placement {
	case config.PlacementPath:
		request.URL.Path = appendToPath(request.URL.Path, value)
	case config.PlacementQuery:
		query := request.URL.Query()
		query.Set(key, value)
		request.URL.RawQuery = query.Encode()
	case config.PlacementHeader:
		request.Header.Set(key, value)
	case config.PlacementCookie:
		request.AddCookie(&http.Cookie{Name: key, Value: value})
	}
}

// applyPadding adds the random-length padding every request carries.
//
// Without obfs mode it rides as the query of a Referer header that points at
// the request's own URL: a header no CDN strips, and one a real page would
// send too. It is built before the session id goes into the path, as Xray
// builds it — the server reads only the query and ignores the rest.
func applyPadding(request *http.Request, options *config.Resolved) {
	length := int(options.XPaddingBytes.Pick())
	placement, key, header, method := config.PlacementQueryInHeader, "x_padding", "Referer", config.PaddingRepeatX
	if options.XPaddingObfsMode {
		placement, key, header, method = options.XPaddingPlacement, options.XPaddingKey, options.XPaddingHeader, options.XPaddingMethod
	}
	value := generatePadding(method, length)
	switch placement {
	case config.PlacementHeader:
		request.Header.Set(header, value)
	case config.PlacementQueryInHeader:
		carrier := *request.URL
		carrier.RawQuery = key + "=" + value
		request.Header.Set(header, carrier.String())
	case config.PlacementCookie:
		if key != "" && value != "" {
			request.AddCookie(&http.Cookie{Name: key, Value: value, Path: "/"})
		}
	case config.PlacementQuery:
		if key != "" && value != "" {
			query := request.URL.Query()
			query.Set(key, value)
			request.URL.RawQuery = query.Encode()
		}
	}
}

func appendToPath(path, value string) string {
	if strings.HasSuffix(path, "/") {
		return path + value
	}
	return path + "/" + value
}

// newSessionID names one proxied connection to the server: a random UUID, or
// a draw from the configured alphabet.
func newSessionID(options *config.Resolved) string {
	length := int(options.SessionIDLength.Pick())
	if table := options.SessionIDTable; table != "" && length > 0 {
		id := make([]byte, length)
		for i := range id {
			id[i] = table[rand.IntN(len(table))]
		}
		return string(id)
	}
	var raw [16]byte
	if _, err := crand.Read(raw[:]); err != nil {
		for i := range raw {
			raw[i] = byte(rand.IntN(256))
		}
	}
	raw[6] = (raw[6] & 0x0f) | 0x40 // version 4
	raw[8] = (raw[8] & 0x3f) | 0x80 // RFC 4122 variant
	text := hex.EncodeToString(raw[:])
	return text[0:8] + "-" + text[8:12] + "-" + text[12:16] + "-" + text[16:20] + "-" + text[20:32]
}

// baseURL is the URL every request of a client starts from.
func baseURL(options *config.Resolved, secure bool, host string) url.URL {
	target := url.URL{
		Scheme:   "http",
		Host:     host,
		Path:     options.NormalizedPath(),
		RawQuery: options.NormalizedQuery(),
	}
	if secure {
		target.Scheme = "https"
	}
	return target
}
