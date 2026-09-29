package xhttp

import (
	"context"

	"github.com/Makhkets/commy/core/xhttp/config"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/dialer"
	"github.com/sagernet/sing-box/common/tls"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
)

// newDownloadTLS builds the download route's TLS from its `tls` block, the way
// sing-box builds an outbound's own: the same decoder that refuses unknown
// fields, the same constructor, so REALITY, uTLS and plain TLS all mean what
// they mean on the main route. No block, no TLS — plain HTTP/1.1, which Xray
// allows for a download route whatever the main one does.
//
// The server name falls back to the download server's address, as Xray's
// falls back to the download destination.
func newDownloadTLS(ctx context.Context, download *config.ResolvedDownload) (tls.Config, error) {
	if len(download.TLS) == 0 {
		return nil, nil
	}
	var options option.OutboundTLSOptions
	if err := json.UnmarshalContextDisallowUnknownFields(ctx, download.TLS, &options); err != nil {
		return nil, E.Cause(err, "tls")
	}
	return tls.NewClientWithOptions(tls.ClientOptions{
		Context:       ctx,
		Logger:        packageLogger{},
		ServerAddress: download.Server,
		Options:       options,
	})
}

// newDownloadDialer is the outbound's own dialer — protected sockets, the
// interface it binds, its detour — made able to reach a download server
// given by name.
//
// sing-box wraps an outbound's dialer in a resolver only when the outbound's
// own server is a domain. The deployment downloadSettings exists for is the
// opposite: REALITY straight to an IP for the upload, a CDN name for the
// download — and a bare dialer answers a name with "domain not resolved".
// The wrapper resolves the name the way sing-box resolves an outbound's
// server: through the default domain resolver of the route, which Commy
// always sets. A detour resolves on its own, and a dialer that already
// resolves needs nothing more.
func newDownloadDialer(ctx context.Context, outbound N.Dialer, server M.Socksaddr) N.Dialer {
	if !server.IsDomain() {
		return outbound
	}
	switch outbound.(type) {
	case dialer.ResolveDialer, dialer.ParallelInterfaceResolveDialer, *dialer.DetourDialer:
		return outbound
	}
	var (
		resolver string
		query    adapter.DNSQueryOptions
	)
	if network := service.FromContext[adapter.NetworkManager](ctx); network != nil {
		defaults := network.DefaultOptions()
		resolver, query = defaults.DomainResolver, defaults.DomainResolveOptions
	}
	// The resolver is named rather than looked up: the dialer finds it on
	// its first dial, when every DNS transport is sure to exist.
	return dialer.NewResolveDialer(ctx, outbound, true, resolver, query, 0)
}

// packageLogger forwards to sing-box's package-level logger at the moment
// something is logged, not at construction: libbox points that logger at
// the running instance only after the outbounds — and with them this
// transport — have been built.
type packageLogger struct{}

func (packageLogger) Trace(args ...any) { log.Trace(args...) }
func (packageLogger) Debug(args ...any) { log.Debug(args...) }
func (packageLogger) Info(args ...any)  { log.Info(args...) }
func (packageLogger) Warn(args ...any)  { log.Warn(args...) }
func (packageLogger) Error(args ...any) { log.Error(args...) }
func (packageLogger) Fatal(args ...any) { log.Fatal(args...) }
func (packageLogger) Panic(args ...any) { log.Panic(args...) }

func (packageLogger) TraceContext(ctx context.Context, args ...any) { log.TraceContext(ctx, args...) }
func (packageLogger) DebugContext(ctx context.Context, args ...any) { log.DebugContext(ctx, args...) }
func (packageLogger) InfoContext(ctx context.Context, args ...any)  { log.InfoContext(ctx, args...) }
func (packageLogger) WarnContext(ctx context.Context, args ...any)  { log.WarnContext(ctx, args...) }
func (packageLogger) ErrorContext(ctx context.Context, args ...any) { log.ErrorContext(ctx, args...) }
func (packageLogger) FatalContext(ctx context.Context, args ...any) { log.FatalContext(ctx, args...) }
func (packageLogger) PanicContext(ctx context.Context, args ...any) { log.PanicContext(ctx, args...) }
