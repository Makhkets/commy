package latency

import (
	"context"
	"errors"
	"net"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/dns"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"

	mDNS "github.com/miekg/dns"
)

// Context is ctx with sing-box's registries, and with "local" DNS answered by
// the operating system's resolver.
//
// sing-box implements "local" on Unix by reading /etc/resolv.conf, and
// Android has none: every lookup would go to 127.0.0.1:53 and a server named
// by host name could never be dialled. The tunnel gets Android's resolver
// from the app (AndroidDnsTransport); a probe has no platform to ask, and
// needs none — Go itself resolves through the C library on Android
// (net/conf.go: "DNS requests don't work on Android, so prefer the cgo
// resolver"), which is netd, the same resolver the app's other lookups use.
func Context(ctx context.Context) context.Context {
	registry := include.DNSTransportRegistry()
	dns.RegisterTransport[option.LocalDNSServerOptions](registry, C.DNSTypeLocal, newSystemResolver)
	return box.Context(ctx, include.InboundRegistry(), include.OutboundRegistry(), include.EndpointRegistry(), registry, include.ServiceRegistry())
}

// systemResolver answers A and AAAA through net.DefaultResolver. Those are
// the only questions an outbound asks about its server.
type systemResolver struct {
	dns.TransportAdapter
}

func newSystemResolver(_ context.Context, _ log.ContextLogger, tag string, options option.LocalDNSServerOptions) (adapter.DNSTransport, error) {
	return &systemResolver{TransportAdapter: dns.NewTransportAdapterWithLocalOptions(C.DNSTypeLocal, tag, options)}, nil
}

func (r *systemResolver) Start(adapter.StartStage) error { return nil }

func (r *systemResolver) Close() error { return nil }

func (r *systemResolver) Reset() {}

func (r *systemResolver) Exchange(ctx context.Context, message *mDNS.Msg) (*mDNS.Msg, error) {
	if len(message.Question) == 0 {
		return nil, E.New("a query with no question")
	}
	question := message.Question[0]
	var network string
	switch question.Qtype {
	case mDNS.TypeA:
		network = "ip4"
	case mDNS.TypeAAAA:
		network = "ip6"
	default:
		return nil, E.New("the system resolver answers only A and AAAA")
	}
	addresses, err := net.DefaultResolver.LookupNetIP(ctx, network, dns.FqdnToDomain(question.Name))
	if err != nil {
		var notFound *net.DNSError
		if errors.As(err, &notFound) && notFound.IsNotFound {
			// A name with no address of this family is an answer, not a
			// failure: an empty one.
			return dns.FixedResponse(message.Id, question, nil, C.DefaultDNSTTL), nil
		}
		return nil, err
	}
	return dns.FixedResponse(message.Id, question, addresses, C.DefaultDNSTTL), nil
}
