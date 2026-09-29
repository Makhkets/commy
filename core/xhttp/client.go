package xhttp

import (
	"context"
	"io"
	"net"
	"net/http/httptrace"
	"sync"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/tls"
	"github.com/sagernet/sing-box/log"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"golang.org/x/net/http2"
)

var _ adapter.V2RayClientTransport = (*Client)(nil)

// Client is the XHTTP transport of one outbound.
type Client struct {
	ctx  context.Context
	mode string
	// upload carries stream-one, the stream-up POST and the packet-up POSTs;
	// its options make the session id. download carries the GET of stream-up
	// and packet-up — the same route unless a download route was given
	// (Xray's downloadSettings).
	upload   *route
	download *route

	// access guards both routes' pools: muxManager is not safe for
	// concurrent use, and one connection takes a client from each.
	access sync.Mutex
	// reset is closed by Close; connections still draining give up on it. Each
	// Close installs a fresh one for the connections that come after.
	reset chan struct{}
}

// route is one way to the server: where requests go, how they are dressed,
// and the pool of connections that carries them.
type route struct {
	options     config.Resolved
	httpVersion string
	requestURL  string
	mux         *muxManager
}

// NewClient builds the transport. It dials nothing: connections are made when
// the first proxied connection asks for one.
func NewClient(
	ctx context.Context,
	dialer N.Dialer,
	serverAddr M.Socksaddr,
	options config.Options,
	tlsConfig tls.Config,
) (adapter.V2RayClientTransport, error) {
	resolved, err := options.Resolve()
	if err != nil {
		return nil, err
	}
	upload, err := newRoute(dialer, serverAddr, resolved, tlsConfig)
	if err != nil {
		return nil, err
	}
	reality := tlsConfig != nil && isReality(tlsConfig)
	client := &Client{
		ctx:      ctx,
		mode:     decideMode(resolved.Mode, reality, resolved.Download != nil),
		upload:   upload,
		download: upload,
		reset:    make(chan struct{}),
	}
	if d := resolved.Download; d != nil {
		addr := M.ParseSocksaddrHostPort(d.Server, d.ServerPort)
		downloadTLS, err := newDownloadTLS(ctx, d)
		if err != nil {
			return nil, E.Cause(err, "xhttp download")
		}
		client.download, err = newRoute(newDownloadDialer(ctx, dialer, addr), addr, d.Resolved, downloadTLS)
		if err != nil {
			return nil, E.Cause(err, "xhttp download")
		}
	}
	return client, nil
}

// newRoute works out one route: its HTTP version, the URL its requests go
// to, and a pool that dials serverAddr through dialer when a connection is
// wanted.
func newRoute(
	dialer N.Dialer,
	serverAddr M.Socksaddr,
	resolved config.Resolved,
	tlsConfig tls.Config,
) (*route, error) {
	reality := tlsConfig != nil && isReality(tlsConfig)
	httpVersion := decideHTTPVersion(tlsConfig, reality)
	if tlsConfig != nil && httpVersion == httpVersion2 && len(tlsConfig.NextProtos()) == 0 {
		tlsConfig.SetNextProtos([]string{http2.NextProtoTLS})
	}

	// Priority: host > TLS server name > address. The port is left out, as
	// Xray leaves it out: the value is a Host header, not a dial target.
	host := resolved.Host
	if host == "" && tlsConfig != nil {
		host = tlsConfig.ServerName()
	}
	if host == "" {
		host = serverAddr.AddrString()
	}
	requestURL := baseURL(&resolved, tlsConfig != nil, host)

	r := &route{
		options:     resolved,
		httpVersion: httpVersion,
		requestURL:  requestURL.String(),
	}
	var tlsDialer tls.Dialer
	if tlsConfig != nil {
		tlsDialer = tls.NewDialer(dialer, tlsConfig)
	}
	dial := func(ctx context.Context) (net.Conn, error) {
		if tlsDialer != nil {
			return tlsDialer.DialTLSContext(ctx, serverAddr)
		}
		return dialer.DialContext(ctx, N.NetworkTCP, serverAddr)
	}

	if httpVersion == httpVersion3 {
		// Build one now and throw it away: the only thing that can fail is the
		// TLS configuration, and that is a fact about the outbound, not about
		// a connection.
		_, shutdown, err := newHTTP3(&r.options, dialer, serverAddr, tlsConfig)
		if err != nil {
			return nil, err
		}
		shutdown()
	}
	r.mux = newMuxManager(&r.options, func() *httpClient {
		if httpVersion != httpVersion3 {
			return newHTTPClient(&r.options, httpVersion, dial, nil, nil)
		}
		transport, shutdown, err := newHTTP3(&r.options, dialer, serverAddr, tlsConfig)
		if err != nil {
			// Checked above with the same arguments; kept so that a change
			// there cannot turn into a nil round tripper here.
			closed := newHTTPClient(&r.options, httpVersion1, dial, nil, nil)
			closed.close()
			return closed
		}
		return newHTTPClient(&r.options, httpVersion, dial, transport, shutdown)
	})
	return r, nil
}

// decideHTTPVersion mirrors Xray: REALITY is HTTP/2, no TLS is HTTP/1.1, and
// otherwise a single ALPN entry picks the version while anything else means
// HTTP/2.
func decideHTTPVersion(tlsConfig tls.Config, reality bool) string {
	if reality {
		return httpVersion2
	}
	if tlsConfig == nil {
		return httpVersion1
	}
	protos := tlsConfig.NextProtos()
	if len(protos) != 1 {
		return httpVersion2
	}
	switch protos[0] {
	case "http/1.1":
		return httpVersion1
	case "h3":
		return httpVersion3
	default:
		return httpVersion2
	}
}

// decideMode resolves `auto`. With REALITY the client talks to the server
// directly, nothing in between buffers, and one request can carry both
// directions — unless the download is to take another route, which one
// request cannot do; then stream-up, as Xray decides it. Anything else may
// sit behind a CDN, and packet-up is the mode that survives one.
func decideMode(mode string, reality, download bool) string {
	if mode != config.ModeAuto {
		return mode
	}
	if reality {
		if download {
			return config.ModeStreamUp
		}
		return config.ModeStreamOne
	}
	return config.ModePacketUp
}

// acquireConn picks the HTTP clients for a new proxied connection — one from
// each route, the same one when there is a single route — and takes a hold
// on each.
//
// The holds are taken under the same lock the pools retire clients under.
// Taken outside it, another dial could retire a client in between, find
// nobody holding it, and close it under the caller's feet.
//
// The channel returned is the one the next Close will close.
func (c *Client) acquireConn() (up, down *muxClient, reset <-chan struct{}) {
	c.access.Lock()
	defer c.access.Unlock()
	up = c.upload.mux.get()
	up.running.Add(1)
	down = up
	if c.download != c.upload {
		down = c.download.mux.get()
		down.running.Add(1)
	}
	return up, down, c.reset
}

// acquireUpload picks a client of the upload route for an uploader whose
// client has been retired, holding it for uploads. Never the download route:
// a CDN in front of the download is exactly where the posts must not go.
func (c *Client) acquireUpload() *muxClient {
	c.access.Lock()
	defer c.access.Unlock()
	client := c.upload.mux.get()
	client.holdUpload()
	return client
}

// DialContext opens one proxied connection.
func (c *Client) DialContext(ctx context.Context) (net.Conn, error) {
	up, down, reset := c.acquireConn()
	release := up.doneRunning
	if down != up {
		release = func() {
			down.doneRunning()
			up.doneRunning()
		}
	}
	// The package-level logger, looked up on every use: a transport is handed
	// no logger of its own, and libbox points this one at the running
	// instance's log only after the outbounds have been built. No host in it:
	// the log is exported, and a server's name is the user's (R3).
	if c.download != c.upload {
		log.DebugContext(ctx, "xhttp: dialing, mode ", c.mode, ", HTTP/", c.upload.httpVersion,
			", download over HTTP/", c.download.httpVersion)
	} else {
		log.DebugContext(ctx, "xhttp: dialing, mode ", c.mode, ", HTTP/", c.upload.httpVersion)
	}

	flushed := make(chan struct{})
	var flushedOnce sync.Once
	markFlushed := func() { flushedOnce.Do(func() { close(flushed) }) }
	conn := &splitConn{onClose: release, flushed: flushed, abandon: reset}
	fail := func(err error) (net.Conn, error) {
		release()
		return nil, E.Cause(err, "xhttp")
	}

	if c.mode == config.ModeStreamOne {
		up.leftRequests.Add(-1)
		bodyReader, bodyWriter := io.Pipe()
		reader, addrs, err := up.http.openStream(ctx, c.upload.requestURL, "", bodyReader, false, markFlushed)
		if err != nil {
			return fail(err)
		}
		conn.reader, conn.writer = reader, bodyWriter
		conn.localAddr, conn.remoteAddr = addrs.local, addrs.remote
		return conn, nil
	}

	// The id comes from the upload route, as Xray makes it from the main
	// config; the GET carries it however the download route places it.
	sessionID := newSessionID(&c.upload.options)
	down.leftRequests.Add(-1)
	reader, addrs, err := down.http.openStream(ctx, c.download.requestURL, sessionID, nil, false, nil)
	if err != nil {
		return fail(err)
	}
	conn.reader = reader
	conn.localAddr, conn.remoteAddr = addrs.local, addrs.remote

	if c.mode == config.ModeStreamUp {
		up.leftRequests.Add(-1)
		bodyReader, bodyWriter := io.Pipe()
		upload, _, err := up.http.openStream(ctx, c.upload.requestURL, sessionID, bodyReader, true, markFlushed)
		if err != nil {
			_ = reader.Close()
			return fail(err)
		}
		conn.writer = &streamUpWriter{PipeWriter: bodyWriter, response: upload, flushed: flushed}
		return conn, nil
	}

	maxUpload := int(c.upload.options.ScMaxEachPostBytes.Pick())
	queue := newUploadQueue(maxUpload)
	conn.writer = queue
	go func() {
		defer markFlushed()
		c.uploadLoop(context.WithoutCancel(ctx), queue, reader, up, sessionID)
	}()
	return conn, nil
}

// streamUpWriter is the upload half of stream-up: the request body, plus the
// response that has to be let go of once the body has been sent.
type streamUpWriter struct {
	*io.PipeWriter
	response *lateReader
	flushed  <-chan struct{}
}

func (w *streamUpWriter) Close() error {
	err := w.PipeWriter.Close()
	// The response only ever carries keep-alive padding, but cancelling it
	// resets the stream — and a stream reset before its body has been written
	// out takes the unwritten tail with it.
	go func() {
		timer := time.NewTimer(drainTimeout)
		defer timer.Stop()
		select {
		case <-w.flushed:
		case <-timer.C:
		}
		_ = w.response.Close()
	}()
	return err
}

// uploadLoop turns what gathers in [queue] into sequenced POSTs.
//
// Requests are started one after another — the next is not started until the
// previous has been written out — but none waits for its predecessor's
// response. The order of writes keeps the server's reordering buffer nearly
// empty; not waiting for responses keeps the upload from costing a round trip
// per packet.
func (c *Client) uploadLoop(
	ctx context.Context,
	queue *uploadQueue,
	download *lateReader,
	first *muxClient,
	sessionID string,
) {
	var (
		seq       int64
		lastWrite time.Time
		inFlight  sync.WaitGroup
	)
	// Returning means "flushed" to whoever is closing the connection, so the
	// posts still on their way have to be waited for.
	defer inFlight.Wait()
	// The uploader holds whichever client it currently posts through. The
	// proxied connection holds only the client it started on, and the uploader
	// outgrows that one as soon as it has used up its quota of requests.
	poster := first
	poster.holdUpload()
	defer func() { poster.doneUpload() }()
	for {
		payload, err := queue.next()
		if err != nil {
			return
		}

		if interval := c.upload.options.ScMinPostsIntervalMs.Pick(); interval > 0 && !lastWrite.IsZero() {
			if wait := time.Duration(interval)*time.Millisecond - time.Since(lastWrite); wait > 0 {
				time.Sleep(wait)
			}
		}
		lastWrite = time.Now()

		// The connection this upload started on may have served its quota of
		// requests, or outlived its welcome. The download stays where it is;
		// later uploads move to a fresh connection, and the server matches
		// them to the session by id, not by connection.
		if poster.leftRequests.Add(-1) <= 0 ||
			(!poster.unreusableAt.IsZero() && lastWrite.After(poster.unreusableAt)) {
			next := c.acquireUpload()
			poster.doneUpload()
			poster = next
		}

		written := make(chan struct{})
		var writtenOnce sync.Once
		markWritten := func() { writtenOnce.Do(func() { close(written) }) }
		traced := httptrace.WithClientTrace(ctx, &httptrace.ClientTrace{
			WroteRequest: func(httptrace.WroteRequestInfo) { markWritten() },
		})

		inFlight.Add(1)
		poster.holdUpload()
		go func(client *muxClient, seq int64) {
			defer inFlight.Done()
			defer client.doneUpload()
			err := client.http.postPacket(traced, c.upload.requestURL, sessionID, seq, payload)
			markWritten()
			if err != nil {
				log.DebugContext(ctx, "xhttp: upload failed: ", err)
				// The server is now missing a piece of the stream. Nothing
				// sent after it can be delivered, so stop both directions
				// rather than let the connection hang until a timeout.
				queue.fail(E.Cause(err, "xhttp upload"))
				download.fail(E.Cause(err, "xhttp upload"))
				_ = download.Close()
			}
		}(poster, seq)
		seq++
		<-written
	}
}

// Close drops every connection of the transport — and leaves the transport
// usable.
//
// That second half is sing-box's contract, not a convenience. An outbound calls
// Close when it shuts down, and ALSO from InterfaceUpdated: whenever the
// default network changes, so that connections bound to the old network are
// not reused on the new one. On Android the platform reports the default
// interface the moment the tunnel starts. A Close that was final turned the
// transport into one that answered every dial with "use of closed network
// connection" from the first second — invisible on a desktop, where nothing
// reports an interface, and total on a phone.
func (c *Client) Close() error {
	c.access.Lock()
	defer c.access.Unlock()
	close(c.reset)
	c.reset = make(chan struct{})
	c.upload.mux.closeAll()
	if c.download != c.upload {
		c.download.mux.closeAll()
	}
	return nil
}
