package xhttp

import (
	"context"
	"net/http"
	"runtime"
	"time"

	"github.com/Makhkets/commy/core/xhttp/config"
	"github.com/sagernet/quic-go"
	"github.com/sagernet/quic-go/http3"
	"github.com/sagernet/sing-box/common/tls"
	"github.com/sagernet/sing/common/bufio"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// newHTTP3 builds the HTTP/3 round tripper of one XMUX client.
//
// QUIC does its own TLS, so this is the one place the transport needs the
// standard library's configuration rather than sing-box's. REALITY and uTLS
// cannot give one — neither exists over QUIC — and say so here, when the
// outbound is created, instead of at the first connection.
func newHTTP3(
	options *config.Resolved,
	dialer N.Dialer,
	serverAddr M.Socksaddr,
	tlsConfig tls.Config,
) (http.RoundTripper, func(), error) {
	stdConfig, err := tlsConfig.STDConfig()
	if err != nil {
		return nil, nil, E.Cause(err, "HTTP/3 needs plain TLS (no uTLS fingerprint, no REALITY)")
	}

	keepAlive := time.Duration(options.HKeepAlivePeriod) * time.Second
	if keepAlive == 0 {
		keepAlive = h3KeepAlivePeriod
	}
	if keepAlive < 0 {
		keepAlive = 0
	}
	quicConfig := &quic.Config{
		MaxIdleTimeout:  connIdleTimeout,
		KeepAlivePeriod: keepAlive,
		// The default of quic-go's HTTP/3 client, spelled out: a server has no
		// business opening streams towards us.
		MaxIncomingStreams: -1,
		// Path MTU discovery sends probes that a mobile network's middleboxes
		// like to eat; Xray switches it off everywhere but desktop systems.
		DisablePathMTUDiscovery: runtime.GOOS != "linux" &&
			runtime.GOOS != "windows" && runtime.GOOS != "darwin",
	}

	transport := &http3.Transport{
		TLSClientConfig: stdConfig,
		QUICConfig:      quicConfig,
		Dial: func(ctx context.Context, _ string, tlsCfg *tls.STDConfig, cfg *quic.Config) (*quic.Conn, error) {
			conn, err := dialer.DialContext(ctx, N.NetworkUDP, serverAddr)
			if err != nil {
				return nil, err
			}
			quicConn, err := quic.DialEarly(ctx, bufio.NewUnbindPacketConn(conn), conn.RemoteAddr(), tlsCfg, cfg)
			if err != nil {
				_ = conn.Close()
				return nil, err
			}
			// quic-go does not take ownership of the packet conn it is given:
			// when the connection ends it only stops reading from it.
			context.AfterFunc(quicConn.Context(), func() { _ = conn.Close() })
			return quicConn, nil
		},
	}
	return transport, func() { _ = transport.Close() }, nil
}
