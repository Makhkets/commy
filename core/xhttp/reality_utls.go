//go:build with_utls

package xhttp

import "github.com/sagernet/sing-box/common/tls"

// isReality reports whether [config] is a REALITY client.
//
// The transport is handed a finished TLS configuration, not the options it was
// made from, and REALITY changes two protocol decisions: it is always HTTP/2,
// and `auto` resolves to stream-one. The type lives behind the with_utls tag,
// so the question does too.
func isReality(config tls.Config) bool {
	_, reality := config.(*tls.RealityClientConfig)
	return reality
}
