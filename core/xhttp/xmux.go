package xhttp

import (
	"math"
	"math/rand/v2"
	"sync/atomic"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
)

// XMUX decides which HTTP connection a new proxied connection rides on.
//
// HTTP/2 would happily put every stream of the tunnel on one TCP connection
// for as long as the app runs. That is a fingerprint (no browser does it) and
// a fragility (one stalled connection stalls everything). So connections are
// spread over a small pool, and each member is retired after it has carried
// so many streams, served so many requests, or lived so long. The limits are
// drawn from ranges, per connection, so no two age the same way.

// muxClient is one HTTP connection and the account of what it has carried.
type muxClient struct {
	http *httpClient

	// running counts proxied connections that started on this client. It is
	// what max_concurrency is measured against.
	running atomic.Int32
	// uploads counts what else still needs the client alive: packet-up
	// uploaders that moved here from a retired client, and their posts in
	// flight. Kept apart from running so that it does not count against
	// max_concurrency — Xray counts connections there, not requests.
	uploads atomic.Int32
	// leftUsage is how many more proxied connections may start here; -1 means
	// any number. Read and written only under the manager's lock.
	leftUsage int32
	// leftRequests is how many more HTTP requests may be sent here.
	leftRequests atomic.Int32
	// unreusableAt is when the client stops taking new work. Zero: never.
	unreusableAt time.Time
	// retired is set once the manager has dropped the client; it is closed as
	// soon as the last proxied connection on it ends.
	retired atomic.Bool
}

func (c *muxClient) doneRunning() {
	c.running.Add(-1)
	c.closeIfIdle()
}

// holdUpload keeps the client alive for an upload. The caller must already
// hold the client some other way — a retired client with no holders is closed,
// and a hold taken after that would be a hold on nothing.
func (c *muxClient) holdUpload() { c.uploads.Add(1) }

func (c *muxClient) doneUpload() {
	c.uploads.Add(-1)
	c.closeIfIdle()
}

func (c *muxClient) closeIfIdle() {
	if c.retired.Load() && c.running.Load() <= 0 && c.uploads.Load() <= 0 {
		c.http.close()
	}
}

// exhausted reports whether the client must not be handed out again.
func (c *muxClient) exhausted(now time.Time) bool {
	return c.http.isClosed() ||
		c.leftUsage == 0 ||
		c.leftRequests.Load() <= 0 ||
		(!c.unreusableAt.IsZero() && now.After(c.unreusableAt))
}

// muxManager owns the pool. It is not safe for concurrent use; the transport
// calls it under its own lock.
type muxManager struct {
	options     *config.Resolved
	concurrency int32
	connections int32
	newHTTP     func() *httpClient
	clients     []*muxClient
}

func newMuxManager(options *config.Resolved, newHTTP func() *httpClient) *muxManager {
	return &muxManager{
		options:     options,
		concurrency: options.MaxConcurrency.Pick(),
		connections: options.MaxConnections.Pick(),
		newHTTP:     newHTTP,
	}
}

func (m *muxManager) create() *muxClient {
	client := &muxClient{http: m.newHTTP(), leftUsage: -1}
	if times := m.options.CMaxReuseTimes.Pick(); times > 0 {
		client.leftUsage = times - 1
	}
	client.leftRequests.Store(math.MaxInt32)
	if times := m.options.HMaxRequestTimes.Pick(); times > 0 {
		client.leftRequests.Store(times)
	}
	if secs := m.options.HMaxReusableSecs.Pick(); secs > 0 {
		client.unreusableAt = time.Now().Add(time.Duration(secs) * time.Second)
	}
	m.clients = append(m.clients, client)
	return client
}

// get returns the client the next proxied connection should use.
func (m *muxManager) get() *muxClient {
	now := time.Now()
	kept := m.clients[:0]
	for _, client := range m.clients {
		if client.exhausted(now) {
			client.retired.Store(true)
			client.closeIfIdle()
			continue
		}
		kept = append(kept, client)
	}
	clear(m.clients[len(kept):])
	m.clients = kept

	if len(m.clients) == 0 {
		return m.create()
	}
	if m.connections > 0 && len(m.clients) < int(m.connections) {
		return m.create()
	}

	candidates := m.clients
	if m.concurrency > 0 {
		candidates = nil
		for _, client := range m.clients {
			if client.running.Load() < m.concurrency {
				candidates = append(candidates, client)
			}
		}
		if len(candidates) == 0 {
			return m.create()
		}
	}

	client := candidates[rand.IntN(len(candidates))]
	if client.leftUsage > 0 {
		client.leftUsage--
	}
	return client
}

// closeAll drops every client, carrying connections or not.
func (m *muxManager) closeAll() {
	for _, client := range m.clients {
		client.retired.Store(true)
		client.http.close()
	}
	m.clients = nil
}
