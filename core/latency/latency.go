// Package latency times proxy servers with or without a tunnel: it starts
// their outbounds in a sing-box instance of their own, sends one GET through
// each, and stops the instance.
//
// A running core can measure its own outbounds, and Commy uses that for
// "Check". But the moment a user most wants numbers is before connecting —
// which of these servers works at all? — and a core that is not running
// answers nothing. The only number available then used to be how long a
// server takes to accept a TCP connection, which says nothing about whether
// it carries traffic: a REALITY server that refuses this client accepts the
// connection just as fast as one that works.
//
// So this package brings up exactly the outbounds it is given — no inbound,
// no TUN, no routing — and measures each the way a user's traffic would go
// through it. The request leaves through the user's own server and nowhere
// else, which is why rule R1 has nothing to say about it: the device talks to
// the host the user entered, and the probe URL is fetched from there.
//
// The app reaches this through core/mobile, which gomobile binds next to
// libbox.
package latency

import (
	"context"
	"crypto/tls"
	stdjson "encoding/json"
	"net"
	"net/http"
	"net/url"
	"sync"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/common/ntp"
	"github.com/sagernet/sing/service"
)

// DefaultLink is what gets requested when the caller names nothing — the
// same page sing-box's own URL test asks for.
const DefaultLink = "https://www.gstatic.com/generate_204"

// Concurrency is how many servers are measured at once.
//
// The number sing-box uses for a group test. More would time the device's own
// link more than the servers; fewer makes a subscription of thirty wait.
const Concurrency = 10

// MeasureConfig measures every outbound and endpoint of the configuration in
// content and answers with a JSON object of tag to milliseconds, where 0 is
// "did not answer".
//
// ctx must carry the registries: Context gives the ones a probe wants.
func MeasureConfig(ctx context.Context, content string, link string, timeout time.Duration) (string, error) {
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(content))
	if err != nil {
		return "", E.Cause(err, "decode config")
	}
	delays, err := Measure(ctx, options, link, timeout)
	if err != nil {
		return "", err
	}
	answer, err := stdjson.Marshal(delays)
	if err != nil {
		return "", err
	}
	return string(answer), nil
}

// Measure starts the outbounds and endpoints of options, measures each with a
// GET to link through it, and closes them again. Each server gets its own
// timeout; one that runs out, refuses or fails its handshake is 0.
//
// Only the instance itself failing — a configuration the core refuses — is an
// error. A server that does not answer is a measurement.
func Measure(ctx context.Context, options option.Options, link string, timeout time.Duration) (map[string]uint16, error) {
	if link == "" {
		link = DefaultLink
	}
	if _, err := url.Parse(link); err != nil {
		return nil, E.Cause(err, "parse probe link")
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// Ours, unless the caller already put one there: see probePlatform.
	if service.FromContext[adapter.PlatformInterface](ctx) == nil {
		ctx = service.ContextWith[adapter.PlatformInterface](ctx, probePlatform{})
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return nil, E.Cause(err, "create probe instance")
	}
	defer instance.Close()
	if err = instance.Start(); err != nil {
		return nil, E.Cause(err, "start probe instance")
	}

	var tags []string
	for _, outbound := range options.Outbounds {
		tags = append(tags, outbound.Tag)
	}
	for _, endpoint := range options.Endpoints {
		tags = append(tags, endpoint.Tag)
	}

	delays := make(map[string]uint16, len(tags))
	var access sync.Mutex
	var wait sync.WaitGroup
	slots := make(chan struct{}, Concurrency)
	for _, tag := range tags {
		dialer, found := dialerOf(instance, tag)
		if !found {
			delays[tag] = 0
			continue
		}
		wait.Add(1)
		go func() {
			defer wait.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			testCtx, testCancel := context.WithTimeout(ctx, timeout)
			defer testCancel()
			delay, _ := Get(testCtx, link, dialer)
			access.Lock()
			delays[tag] = delay
			access.Unlock()
		}()
	}
	wait.Wait()
	return delays, nil
}

func dialerOf(instance *box.Box, tag string) (N.Dialer, bool) {
	if outbound, found := instance.Outbound().Outbound(tag); found {
		return outbound, true
	}
	if endpoint, found := instance.Endpoint().Get(tag); found {
		return endpoint, true
	}
	return nil, false
}

// Get times one GET to link through dialer: from the dial to the response
// headers, which is the whole handshake with the server plus one round trip
// through it — the delay a user feels. A multiplexed outbound is warmed up
// first, as sing-box's own test does, so the number is that of a stream on an
// open session rather than of the session.
//
// It answers when ctx is done, whatever the outbound is doing. Not every
// handshake listens to a context: a SOCKS server that accepts and then says
// nothing holds the dial forever — the first version of this test sat there
// for ten minutes — and a list of servers must not wait on its slowest
// liar. The abandoned attempt ends when its connection does.
func Get(ctx context.Context, link string, dialer N.Dialer) (uint16, error) {
	type answer struct {
		delay uint16
		err   error
	}
	done := make(chan answer, 1)
	go func() {
		delay, err := warmGet(ctx, link, dialer)
		done <- answer{delay, err}
	}()
	select {
	case result := <-done:
		return result.delay, result.err
	case <-ctx.Done():
		return 0, ctx.Err()
	}
}

func warmGet(ctx context.Context, link string, dialer N.Dialer) (uint16, error) {
	if multiplexed, isMultiplexed := dialer.(adapter.OutboundWithMultiplex); isMultiplexed && multiplexed.MultiplexEnabled() {
		if _, err := get(ctx, link, dialer); err != nil {
			return 0, err
		}
	}
	return get(ctx, link, dialer)
}

func get(ctx context.Context, link string, dialer N.Dialer) (uint16, error) {
	linkURL, err := url.Parse(link)
	if err != nil {
		return 0, err
	}
	hostname := linkURL.Hostname()
	port := linkURL.Port()
	if port == "" {
		switch linkURL.Scheme {
		case "http":
			port = "80"
		case "https":
			port = "443"
		default:
			return 0, E.New("probe link scheme is not http or https: ", linkURL.Scheme)
		}
	}

	start := time.Now()
	conn, err := dialer.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddrHostPortStr(hostname, port))
	if err != nil {
		return 0, err
	}
	defer conn.Close()
	// Some outbounds only shake hands on the first write; sing-box's own
	// test restarts the clock here for them, and so does this one.
	if N.NeedHandshakeForWrite(conn) {
		start = time.Now()
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, link, nil)
	if err != nil {
		return 0, err
	}
	client := http.Client{
		Transport: &http.Transport{
			DialContext: func(context.Context, string, string) (net.Conn, error) {
				return conn, nil
			},
			TLSClientConfig: &tls.Config{
				Time:    ntp.TimeFuncFromContext(ctx),
				RootCAs: adapter.RootPoolFromContext(ctx),
			},
		},
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	defer client.CloseIdleConnections()
	response, err := client.Do(request)
	if err != nil {
		return 0, err
	}
	// The headers are the answer. The body of a probe page is the page's
	// business, and reading it would time the page rather than the server.
	_ = response.Body.Close()
	elapsed := time.Since(start) / time.Millisecond
	switch {
	case elapsed < 1:
		// Zero means "no answer" to every reader of this number.
		return 1, nil
	case elapsed > 65535:
		return 65535, nil
	default:
		return uint16(elapsed), nil
	}
}
