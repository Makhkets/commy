//go:build !with_utls

package xhttp

import "github.com/sagernet/sing-box/common/tls"

// isReality is always false here: without with_utls sing-box cannot build a
// REALITY client at all, so no configuration of that kind can arrive.
func isReality(tls.Config) bool { return false }
