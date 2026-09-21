package xhttp

import (
	"net"
	"sync"
)

// connTracker remembers the raw connections an HTTP client has open, so that
// closing the client closes them.
//
// net/http has no "close everything now": CloseIdleConnections leaves a
// connection with a stream on it alone, and a tunnel always has a stream on
// it. sing-box's own HTTP transport reaches into x/net/http2 through
// go:linkname to get at the pool. Every connection here is dialled by us, so
// keeping the list ourselves does the same job without the reach.
type connTracker struct {
	mu     sync.Mutex
	conns  map[*trackedConn]struct{}
	closed bool
}

func (t *connTracker) track(conn net.Conn) (net.Conn, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		_ = conn.Close()
		return nil, net.ErrClosed
	}
	if t.conns == nil {
		t.conns = make(map[*trackedConn]struct{})
	}
	tracked := &trackedConn{Conn: conn, tracker: t}
	t.conns[tracked] = struct{}{}
	return tracked, nil
}

func (t *connTracker) closeAll() {
	t.mu.Lock()
	t.closed = true
	conns := t.conns
	t.conns = nil
	t.mu.Unlock()
	for conn := range conns {
		_ = conn.Conn.Close()
	}
}

type trackedConn struct {
	net.Conn
	tracker *connTracker
	once    sync.Once
}

func (c *trackedConn) Close() error {
	c.once.Do(func() {
		c.tracker.mu.Lock()
		delete(c.tracker.conns, c)
		c.tracker.mu.Unlock()
	})
	return c.Conn.Close()
}

// Upstream lets sing-box see through the wrapper, as its own wrappers do.
func (c *trackedConn) Upstream() any { return c.Conn }
