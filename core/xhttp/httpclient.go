package xhttp

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	E "github.com/sagernet/sing/common/exceptions"
	"golang.org/x/net/http2"
)

// HTTP versions a client can speak, as Xray names them.
const (
	httpVersion1 = "1.1"
	httpVersion2 = "2"
	httpVersion3 = "3"
)

const (
	// How long an HTTP connection with nothing on it is kept.
	connIdleTimeout = 300 * time.Second
	// Chrome pings an idle HTTP/2 connection at this cadence.
	h2KeepAlivePeriod = 45 * time.Second
	// quic-go's HTTP/3 default.
	h3KeepAlivePeriod = 10 * time.Second
)

// dialFunc opens one raw connection to the server: TCP, and TLS on top when
// the outbound has it.
type dialFunc func(ctx context.Context) (net.Conn, error)

// httpClient is one member of the XMUX pool: an HTTP client that owns its
// connections.
type httpClient struct {
	options     *config.Resolved
	httpVersion string

	// streams carries the long-lived requests and, on HTTP/2 and HTTP/3, the
	// packet-up uploads too — they are all streams of the same connection.
	streams *http.Client
	// packets carries packet-up uploads on HTTP/1.1, where a connection holds
	// one request at a time and the download already has one.
	packets *http.Client

	tracker   connTracker
	closeOnce sync.Once
	closed    atomic.Bool
	shutdown  func()
}

// newHTTPClient builds the client for [httpVersion] over [dial]. [h3] is the
// HTTP/3 round tripper and its shutdown, already built, or nil.
func newHTTPClient(
	options *config.Resolved,
	httpVersion string,
	dial dialFunc,
	h3 http.RoundTripper,
	h3Shutdown func(),
) *httpClient {
	client := &httpClient{options: options, httpVersion: httpVersion}
	tracked := func(ctx context.Context) (net.Conn, error) {
		conn, err := dial(ctx)
		if err != nil {
			return nil, err
		}
		return client.tracker.track(conn)
	}

	switch httpVersion {
	case httpVersion3:
		client.streams = &http.Client{Transport: h3}
		client.shutdown = h3Shutdown
	case httpVersion2:
		keepAlive := time.Duration(options.HKeepAlivePeriod) * time.Second
		if keepAlive == 0 {
			keepAlive = h2KeepAlivePeriod
		}
		if keepAlive < 0 {
			keepAlive = 0
		}
		client.streams = &http.Client{Transport: &http2.Transport{
			DialTLSContext: func(ctx context.Context, _, _ string, _ *http2TLSConfig) (net.Conn, error) {
				return tracked(ctx)
			},
			IdleConnTimeout: connIdleTimeout,
			ReadIdleTimeout: keepAlive,
		}}
	default:
		dialHTTP := func(ctx context.Context, _, _ string) (net.Conn, error) {
			return tracked(ctx)
		}
		client.streams = &http.Client{Transport: &http.Transport{
			DialContext:     dialHTTP,
			DialTLSContext:  dialHTTP,
			IdleConnTimeout: connIdleTimeout,
			// A chunked response that never ends cannot give its connection
			// back, and net/http is unhappy trying.
			DisableKeepAlives: true,
		}}
		client.packets = &http.Client{Transport: &http.Transport{
			DialContext:         dialHTTP,
			DialTLSContext:      dialHTTP,
			IdleConnTimeout:     connIdleTimeout,
			MaxIdleConnsPerHost: 8,
		}}
	}
	return client
}

func (c *httpClient) isClosed() bool { return c.closed.Load() }

// close drops every connection of the client, in use or not.
func (c *httpClient) close() {
	c.closeOnce.Do(func() {
		c.closed.Store(true)
		c.tracker.closeAll()
		if c.shutdown != nil {
			c.shutdown()
		}
	})
}

// streamAddrs is what a stream learned about the connection it rides on.
type streamAddrs struct {
	local  net.Addr
	remote net.Addr
}

// openStream starts a long-lived request and returns once there is a
// connection for it to go out on.
//
// With a [body] it is an upload (stream-up, or both directions of stream-one);
// without, it is the download GET. [uploadOnly] marks the stream-up POST, whose
// response carries nothing but keep-alive padding and is thrown away.
//
// The caller's context bounds the connecting — a dial that outlives the
// caller's patience is cancelled — and nothing after it: the stream belongs to
// the proxied connection from then on and ends when that is closed.
func (c *httpClient) openStream(
	ctx context.Context,
	rawURL string,
	sessionID string,
	body io.ReadCloser,
	uploadOnly bool,
	onWritten func(),
) (*lateReader, streamAddrs, error) {
	streamCtx, cancel := context.WithCancel(context.WithoutCancel(ctx))
	reader := newLateReader(cancel)
	if onWritten == nil {
		onWritten = func() {}
	}

	var addrs streamAddrs
	connected := make(chan struct{})
	var connectedOnce sync.Once
	markConnected := func() { connectedOnce.Do(func() { close(connected) }) }

	traced := httptrace.WithClientTrace(streamCtx, &httptrace.ClientTrace{
		GotConn: func(info httptrace.GotConnInfo) {
			// Inside the Once, because this hook can fire again: HTTP/2 retries
			// a refused stream on a fresh connection, and by then the caller is
			// already reading what the first one wrote here.
			connectedOnce.Do(func() {
				if info.Conn != nil {
					addrs = streamAddrs{local: info.Conn.LocalAddr(), remote: info.Conn.RemoteAddr()}
				}
				close(connected)
			})
		},
		// Fires once the body has been written to its end, which for a
		// streamed upload is after the caller closed it.
		WroteRequest: func(httptrace.WroteRequestInfo) { onWritten() },
	})

	method := http.MethodGet
	if body != nil {
		method = c.options.UplinkHTTPMethod
	}
	var requestBody io.Reader
	if body != nil {
		requestBody = body
	}
	request, err := http.NewRequestWithContext(traced, method, rawURL, requestBody)
	if err != nil {
		cancel()
		closeBody(body)
		onWritten()
		return nil, streamAddrs{}, E.Cause(err, "create request")
	}
	fillStreamRequest(request, c.options, sessionID)

	go func() {
		response, err := c.streams.Do(request)
		if err != nil {
			// A request that failed has nothing left to write.
			onWritten()
			// A failed download means the connection under it is gone, and
			// the next proxied connection should not be handed the same one.
			// Our own cancellation says nothing about the connection.
			if !uploadOnly && !errors.Is(err, context.Canceled) {
				c.closed.Store(true)
			}
			reader.fail(E.Cause(err, method, " ", request.URL.Path))
			markConnected()
			closeBody(body)
			cancel()
			return
		}
		markConnected()
		if response.StatusCode != http.StatusOK || uploadOnly {
			_, _ = io.Copy(io.Discard, response.Body)
			_ = response.Body.Close()
			closeBody(body)
			onWritten()
			if response.StatusCode != http.StatusOK {
				reader.fail(E.New("unexpected status: ", response.Status))
			} else {
				reader.fail(io.EOF)
			}
			cancel()
			return
		}
		reader.set(response.Body)
	}()

	select {
	case <-connected:
	case <-ctx.Done():
		_ = reader.Close()
		closeBody(body)
		onWritten()
		return nil, streamAddrs{}, ctx.Err()
	}
	// Already failed: the request never got a connection, or the server turned
	// it down before we looked. There is nothing to hand out, and the cause is
	// worth more to the caller than the closed pipe a later read would report.
	// io.EOF is not a failure — it is a stream-up POST that finished quickly.
	if err := reader.failure(); err != nil && !errors.Is(err, io.EOF) {
		_ = reader.Close()
		return nil, streamAddrs{}, err
	}
	return reader, addrs, nil
}

// postPacket sends one packet-up upload and waits for the server to accept it.
func (c *httpClient) postPacket(
	ctx context.Context,
	rawURL string,
	sessionID string,
	seq int64,
	payload []byte,
) error {
	request, err := http.NewRequestWithContext(ctx, c.options.UplinkHTTPMethod, rawURL, nil)
	if err != nil {
		return E.Cause(err, "create request")
	}
	fillPacketRequest(request, c.options, sessionID, strconv.FormatInt(seq, 10), payload)

	client := c.streams
	if c.packets != nil {
		client = c.packets
	}
	response, err := client.Do(request)
	if err != nil {
		c.closed.Store(true)
		return err
	}
	_, _ = io.Copy(io.Discard, response.Body)
	_ = response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return E.New("unexpected status: ", response.Status)
	}
	return nil
}

func closeBody(body io.Closer) {
	if body != nil {
		_ = body.Close()
	}
}
