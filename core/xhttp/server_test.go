package xhttp

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/Makhkets/commy/core/xhttp/config"
	"golang.org/x/net/http2/hpack"
)

// fakeXray is the server half of XHTTP, for tests.
//
// It is a transcription of requestHandler.ServeHTTP in Xray's
// transport/internet/splithttp/hub.go, and it is deliberately as strict as the
// original: it validates the padding, finds the session id and the sequence
// number where the configuration says they are, reorders packets, and answers
// with Xray's status codes. A client that passes against a lenient double
// proves nothing about a server that is not lenient.
type fakeXray struct {
	t       testing.TB
	options config.Resolved
	path    string
	// serve is what happens to a proxied connection. Default: echo.
	serve func(conn io.ReadWriteCloser)

	sessions sync.Map // string -> *fakeSession

	mu            sync.Mutex
	requests      []recordedRequest
	sessionsEnded atomic.Int32
}

type recordedRequest struct {
	method     string
	path       string
	proto      int
	bodyLen    int
	header     http.Header
	remoteAddr string
}

type fakeSession struct {
	queue     *reorderQueue
	connected chan struct{}
	once      sync.Once
}

func newFakeXray(t testing.TB, options config.Options) *fakeXray {
	t.Helper()
	resolved, err := options.Resolve()
	if err != nil {
		t.Fatalf("server options: %v", err)
	}
	return &fakeXray{t: t, options: resolved, path: resolved.NormalizedPath()}
}

func (s *fakeXray) recorded() []recordedRequest {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.requests)
}

func (s *fakeXray) session(id string) *fakeSession {
	fresh := &fakeSession{queue: newReorderQueue(), connected: make(chan struct{})}
	actual, _ := s.sessions.LoadOrStore(id, fresh)
	return actual.(*fakeSession)
}

func (s *fakeXray) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, s.path) {
		w.WriteHeader(http.StatusNotFound)
		return
	}

	padding := s.extractPadding(r)
	if !s.paddingValid(padding) {
		s.t.Logf("fakeXray: invalid padding length %d on %s %s", len(padding), r.Method, r.URL.Path)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	sessionID, seq := s.extractMeta(r)
	if sessionID == "" && s.options.Mode != config.ModeAuto &&
		s.options.Mode != config.ModeStreamOne && s.options.Mode != config.ModeStreamUp {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	isUplink := r.Method != http.MethodGet || seq != ""

	if isUplink && sessionID != "" {
		session := s.session(sessionID)
		if seq == "" { // stream-up
			s.record(r, -1)
			if s.options.Mode != config.ModeAuto && s.options.Mode != config.ModeStreamUp {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			done := make(chan struct{})
			if err := session.queue.pushReader(r.Body, done); err != nil {
				w.WriteHeader(http.StatusConflict)
				return
			}
			w.Header().Set("X-Accel-Buffering", "no")
			w.Header().Set("Cache-Control", "no-store")
			w.WriteHeader(http.StatusOK)
			select {
			case <-r.Context().Done():
			case <-done:
			}
			return
		}

		if s.options.Mode != config.ModeAuto && s.options.Mode != config.ModePacketUp {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		payload, status := s.extractPayload(r)
		if status != http.StatusOK {
			w.WriteHeader(status)
			return
		}
		s.record(r, len(payload))
		number, err := strconv.ParseUint(seq, 10, 64)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		if err := session.queue.pushPacket(number, payload); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet && sessionID != "" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	// stream-down, or stream-one when there is no session.
	s.record(r, -1)
	var upload io.Reader = r.Body
	if sessionID != "" {
		session := s.session(sessionID)
		session.once.Do(func() { close(session.connected) })
		defer s.sessions.Delete(sessionID)
		upload = session.queue
	}
	w.Header().Set("X-Accel-Buffering", "no")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "text/event-stream")
	w.WriteHeader(http.StatusOK)
	flusher, _ := w.(http.Flusher)
	if flusher != nil {
		flusher.Flush()
	}

	conn := &serverConn{reader: upload, writer: w, flusher: flusher, done: make(chan struct{})}
	serve := s.serve
	if serve == nil {
		serve = func(conn io.ReadWriteCloser) {
			_, _ = io.Copy(conn, conn)
			_ = conn.Close()
		}
	}
	go serve(conn)
	select {
	case <-r.Context().Done():
	case <-conn.done:
	}
	_ = conn.Close()
	if sessionID != "" {
		if session, ok := s.sessions.Load(sessionID); ok {
			session.(*fakeSession).queue.close()
		}
	}
	s.sessionsEnded.Add(1)
}

func (s *fakeXray) record(r *http.Request, bodyLen int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requests = append(s.requests, recordedRequest{
		method:     r.Method,
		path:       r.URL.Path,
		proto:      r.ProtoMajor,
		bodyLen:    bodyLen,
		header:     r.Header.Clone(),
		remoteAddr: r.RemoteAddr,
	})
}

func (s *fakeXray) extractPadding(r *http.Request) string {
	if !s.options.XPaddingObfsMode {
		if referrer := r.Header.Get("Referer"); referrer != "" {
			parsed, err := url.Parse(referrer)
			if err != nil {
				return ""
			}
			return parsed.Query().Get("x_padding")
		}
		return r.URL.Query().Get("x_padding")
	}
	key, header := s.options.XPaddingKey, s.options.XPaddingHeader
	if cookie, err := r.Cookie(key); err == nil && cookie.Value != "" {
		return cookie.Value
	}
	if value := r.Header.Get(header); value != "" {
		if s.options.XPaddingPlacement == config.PlacementHeader {
			return value
		}
		if parsed, err := url.Parse(value); err == nil {
			return parsed.Query().Get(key)
		}
	}
	return r.URL.Query().Get(key)
}

func (s *fakeXray) paddingValid(value string) bool {
	if value == "" {
		return false
	}
	from, to := s.options.XPaddingBytes.From, s.options.XPaddingBytes.To
	if s.options.XPaddingObfsMode && s.options.XPaddingMethod == config.PaddingTokenish {
		n := int32(hpack.HuffmanEncodeLength(value))
		return n >= max(0, from-paddingTolerance) && n <= to+paddingTolerance
	}
	n := int32(len(value))
	return n >= from && n <= to
}

func (s *fakeXray) extractMeta(r *http.Request) (sessionID, seq string) {
	var subpath []string
	part := 0
	if s.options.SessionPlacement == config.PlacementPath || s.options.SeqPlacement == config.PlacementPath {
		subpath = strings.Split(r.URL.Path[len(s.path):], "/")
	}
	read := func(placement, key string) string {
		switch placement {
		case config.PlacementPath:
			if len(subpath) > part {
				part++
				return subpath[part-1]
			}
		case config.PlacementQuery:
			return r.URL.Query().Get(key)
		case config.PlacementHeader:
			return r.Header.Get(key)
		case config.PlacementCookie:
			if cookie, err := r.Cookie(key); err == nil {
				return cookie.Value
			}
		}
		return ""
	}
	sessionID = read(s.options.SessionPlacement, s.options.SessionKey)
	seq = read(s.options.SeqPlacement, s.options.SeqKey)
	return sessionID, seq
}

func (s *fakeXray) extractPayload(r *http.Request) ([]byte, int) {
	placement := s.options.UplinkDataPlacement
	key := s.options.UplinkDataKey
	limit := int(s.options.ScMaxEachPostBytes.To)

	var fromHeader, fromCookie, fromBody []byte
	var err error
	if placement == config.PlacementAuto || placement == config.PlacementHeader {
		var chunks []string
		for i := 0; ; i++ {
			chunk := r.Header.Get(fmt.Sprintf("%s-%d", key, i))
			if chunk == "" {
				break
			}
			chunks = append(chunks, chunk)
		}
		if fromHeader, err = base64.RawURLEncoding.DecodeString(strings.Join(chunks, "")); err != nil {
			return nil, http.StatusBadRequest
		}
	}
	if placement == config.PlacementAuto || placement == config.PlacementCookie {
		var chunks []string
		for i := 0; ; i++ {
			cookie, _ := r.Cookie(fmt.Sprintf("%s_%d", key, i))
			if cookie == nil {
				break
			}
			chunks = append(chunks, cookie.Value)
		}
		if fromCookie, err = base64.RawURLEncoding.DecodeString(strings.Join(chunks, "")); err != nil {
			return nil, http.StatusBadRequest
		}
	}
	if placement == config.PlacementAuto || placement == config.PlacementBody {
		if r.ContentLength > int64(limit) {
			return nil, http.StatusRequestEntityTooLarge
		}
		if fromBody, err = io.ReadAll(io.LimitReader(r.Body, int64(limit)+1)); err != nil {
			return nil, http.StatusBadRequest
		}
	}
	payload := slices.Concat(fromHeader, fromCookie, fromBody)
	if len(payload) > limit {
		return nil, http.StatusRequestEntityTooLarge
	}
	return payload, http.StatusOK
}

// serverConn is the proxied connection as the server sees it.
type serverConn struct {
	reader  io.Reader
	writer  http.ResponseWriter
	flusher http.Flusher

	mu     sync.Mutex
	closed bool
	done   chan struct{}
}

func (c *serverConn) Read(b []byte) (int, error) { return c.reader.Read(b) }

func (c *serverConn) Write(b []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return 0, io.ErrClosedPipe
	}
	n, err := c.writer.Write(b)
	if err == nil && c.flusher != nil {
		c.flusher.Flush()
	}
	return n, err
}

func (c *serverConn) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.closed {
		c.closed = true
		close(c.done)
	}
	return nil
}

// reorderQueue hands the upload to the proxied connection in sequence order,
// whatever order the packets arrived in.
type reorderQueue struct {
	mu      sync.Mutex
	changed *sync.Cond
	packets map[uint64][]byte
	next    uint64
	current *bytes.Reader
	stream  io.Reader
	streamD chan struct{}
	closed  bool
}

const maxBufferedPosts = 30

func newReorderQueue() *reorderQueue {
	q := &reorderQueue{packets: make(map[uint64][]byte)}
	q.changed = sync.NewCond(&q.mu)
	return q
}

func (q *reorderQueue) pushPacket(seq uint64, payload []byte) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed {
		return io.ErrClosedPipe
	}
	if len(q.packets) > maxBufferedPosts {
		return fmt.Errorf("too many buffered posts")
	}
	q.packets[seq] = payload
	q.changed.Broadcast()
	return nil
}

func (q *reorderQueue) pushReader(reader io.Reader, done chan struct{}) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.stream != nil {
		return fmt.Errorf("stream already attached")
	}
	q.stream, q.streamD = reader, done
	q.changed.Broadcast()
	return nil
}

func (q *reorderQueue) Read(b []byte) (int, error) {
	q.mu.Lock()
	for {
		if q.stream != nil {
			stream, done := q.stream, q.streamD
			q.mu.Unlock()
			n, err := stream.Read(b)
			if err != nil {
				select {
				case <-done:
				default:
					close(done)
				}
			}
			return n, err
		}
		if q.current != nil && q.current.Len() > 0 {
			n, _ := q.current.Read(b)
			q.mu.Unlock()
			return n, nil
		}
		if payload, ok := q.packets[q.next]; ok {
			delete(q.packets, q.next)
			q.next++
			q.current = bytes.NewReader(payload)
			continue
		}
		if q.closed {
			q.mu.Unlock()
			return 0, io.EOF
		}
		q.changed.Wait()
	}
}

func (q *reorderQueue) close() {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.closed = true
	q.changed.Broadcast()
}

// countingListener counts the TCP connections a server accepted.
type countingListener struct {
	net.Listener
	accepted atomic.Int32
}

func (l *countingListener) Accept() (net.Conn, error) {
	conn, err := l.Listener.Accept()
	if err == nil {
		l.accepted.Add(1)
	}
	return conn, err
}
