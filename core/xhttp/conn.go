package xhttp

import (
	"context"
	"io"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sagernet/sing/common/baderror"
	M "github.com/sagernet/sing/common/metadata"
)

// drainTimeout bounds how long a closed connection keeps its session open so
// that the last bytes written to it can still reach the server.
const drainTimeout = 3 * time.Second

// splitConn is one proxied connection: a download that is the body of an HTTP
// response, and an upload that is either the body of a request or a queue of
// packets waiting to be posted.
type splitConn struct {
	reader io.ReadCloser
	writer io.WriteCloser

	// flushed is closed once everything written has been handed to the
	// network: the request body has been sent, or the last packet was posted.
	flushed <-chan struct{}
	// abandon is closed when the whole transport shuts down; nothing is worth
	// waiting for after that.
	abandon <-chan struct{}

	closed    atomic.Bool
	closeOnce sync.Once
	onClose   func()

	localAddr  net.Addr
	remoteAddr net.Addr
}

func (c *splitConn) Read(b []byte) (int, error) {
	if c.closed.Load() {
		return 0, net.ErrClosed
	}
	n, err := c.reader.Read(b)
	return n, baderror.WrapH2(err)
}

func (c *splitConn) Write(b []byte) (int, error) {
	if c.closed.Load() {
		return 0, net.ErrClosed
	}
	n, err := c.writer.Write(b)
	return n, baderror.WrapH2(err)
}

// Close ends the connection without losing what was written to it.
//
// The download is what holds the session open on the server, and in every
// mode the upload is sent asynchronously. Tearing the download down the moment
// Close is called — which is what Xray's own client does — races the last
// upload: the server drops the session, and bytes the caller wrote just before
// closing arrive at nothing. A TCP socket never does that to its owner, and a
// proxy that stands in for one should not either. So the upload is closed
// first, and the download is let go only once the upload has been flushed, or
// drainTimeout has passed.
//
// Close itself never waits. sing-box closes connections one after another
// when a tunnel stops, and on a dead network a Close that waited would make
// stopping take seconds per connection.
func (c *splitConn) Close() error {
	c.closeOnce.Do(func() {
		c.closed.Store(true)
		_ = c.writer.Close()
		finish := func() {
			_ = c.reader.Close()
			if c.onClose != nil {
				c.onClose()
			}
		}
		select {
		case <-c.flushed:
			finish()
			return
		default:
		}
		go func() {
			timer := time.NewTimer(drainTimeout)
			defer timer.Stop()
			select {
			case <-c.flushed:
			case <-c.abandon:
			case <-timer.C:
			}
			finish()
		}()
	})
	return nil
}

func (c *splitConn) LocalAddr() net.Addr {
	if c.localAddr != nil {
		return c.localAddr
	}
	return M.Socksaddr{}
}

func (c *splitConn) RemoteAddr() net.Addr {
	if c.remoteAddr != nil {
		return c.remoteAddr
	}
	return M.Socksaddr{}
}

// An HTTP body has no deadlines. Saying so, rather than returning nil and
// ignoring the call, is what makes sing-box wrap the connection in its own
// deadline emulation — the same contract its HTTP/2 transport follows.
func (c *splitConn) SetDeadline(time.Time) error      { return os.ErrInvalid }
func (c *splitConn) SetReadDeadline(time.Time) error  { return os.ErrInvalid }
func (c *splitConn) SetWriteDeadline(time.Time) error { return os.ErrInvalid }

// NeedAdditionalReadDeadline asks sing-box for that emulation.
func (c *splitConn) NeedAdditionalReadDeadline() bool { return true }

// lateReader is a response body that may not have arrived yet.
//
// Opening a stream returns as soon as there is a connection to send the
// request on; the response comes later. Reads wait for it. Waiting for it
// before handing the connection out would add a round trip to every proxied
// connection, which is the cost this transport exists to avoid.
type lateReader struct {
	cancel context.CancelFunc
	ready  chan struct{}

	mu     sync.Mutex
	body   io.ReadCloser
	err    error
	closed bool
	done   bool
}

func newLateReader(cancel context.CancelFunc) *lateReader {
	return &lateReader{cancel: cancel, ready: make(chan struct{})}
}

// set hands over the response body. A reader closed in the meantime closes it.
func (r *lateReader) set(body io.ReadCloser) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.done {
		_ = body.Close()
		return
	}
	r.done = true
	if r.closed {
		_ = body.Close()
		r.err = io.ErrClosedPipe
	} else {
		r.body = body
	}
	close(r.ready)
}

// fail ends the wait with [err]; every read from now on returns it.
func (r *lateReader) fail(err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.done {
		return
	}
	r.done = true
	r.err = err
	close(r.ready)
}

// failure reports the error the stream ended with, if it has ended.
func (r *lateReader) failure() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.err
}

func (r *lateReader) Read(b []byte) (int, error) {
	<-r.ready
	r.mu.Lock()
	body, err := r.body, r.err
	r.mu.Unlock()
	if body == nil {
		if err == nil {
			err = io.ErrClosedPipe
		}
		return 0, err
	}
	return body.Read(b)
}

func (r *lateReader) Close() error {
	r.mu.Lock()
	r.closed = true
	body := r.body
	r.body = nil
	if !r.done {
		r.done = true
		r.err = io.ErrClosedPipe
		close(r.ready)
	} else if r.err == nil {
		r.err = io.ErrClosedPipe
	}
	r.mu.Unlock()
	// Cancelling the request resets the stream, which is how the server learns
	// the session is over. Closing the body alone would only stop reading it.
	r.cancel()
	if body != nil {
		return body.Close()
	}
	return nil
}

// uploadQueue batches writes into packet-up uploads.
//
// A proxied connection writes in small pieces; posting each as its own request
// would cap the upload at a few kilobytes per round trip. So writes land here,
// and whoever posts takes everything that has gathered since the last post.
// The queue holds at most one request's worth: a full queue blocks the writer,
// which is the back-pressure a net.Conn is expected to exert.
type uploadQueue struct {
	mu       sync.Mutex
	changed  *sync.Cond
	pending  []byte
	capacity int
	closed   bool
	err      error
}

func newUploadQueue(capacity int) *uploadQueue {
	q := &uploadQueue{capacity: max(capacity, 1)}
	q.changed = sync.NewCond(&q.mu)
	return q
}

func (q *uploadQueue) Write(b []byte) (int, error) {
	written := 0
	q.mu.Lock()
	defer q.mu.Unlock()
	for len(b) > 0 {
		for len(q.pending) >= q.capacity && !q.closed && q.err == nil {
			q.changed.Wait()
		}
		if q.err != nil {
			return written, q.err
		}
		if q.closed {
			return written, io.ErrClosedPipe
		}
		n := min(len(b), q.capacity-len(q.pending))
		q.pending = append(q.pending, b[:n]...)
		b = b[n:]
		written += n
		q.changed.Broadcast()
	}
	return written, nil
}

// next blocks until there is something to post and returns all of it. After
// Close it keeps returning what was already queued, then io.EOF — the last
// bytes a connection wrote before closing still have to reach the server.
func (q *uploadQueue) next() ([]byte, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	for len(q.pending) == 0 && !q.closed && q.err == nil {
		q.changed.Wait()
	}
	if q.err != nil {
		return nil, q.err
	}
	if len(q.pending) == 0 {
		return nil, io.EOF
	}
	batch := q.pending
	q.pending = nil
	q.changed.Broadcast()
	return batch, nil
}

// fail breaks the queue: a lost upload cannot be papered over, the stream the
// server reassembles would have a hole in it.
func (q *uploadQueue) fail(err error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.err == nil {
		q.err = err
	}
	q.pending = nil
	q.changed.Broadcast()
}

func (q *uploadQueue) Close() error {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.closed = true
	q.changed.Broadcast()
	return nil
}
