// Package mobile is what Commy adds to the libbox API: gomobile binds it next
// to github.com/sagernet/sing-box/experimental/libbox, into the same library
// (scripts/build_core.sh). With the build's -javapkg the Java class is
// io.nekohasekai.mobile.Mobile.
//
// Only types gomobile can carry — strings, numbers, bool, []byte, error —
// and anything richer goes as JSON (CLAUDE.md §5).
package mobile

import (
	"context"
	"time"

	"github.com/Makhkets/commy/core/latency"
)

// URLTestOutbounds measures every outbound of configContent by a GET to link
// through it, in a core instance of its own — no service, no tunnel — and
// answers the JSON object {tag: milliseconds}, 0 for "no answer". Each server
// gets timeoutMillis. See core/latency.
func URLTestOutbounds(configContent string, link string, timeoutMillis int32) (string, error) {
	ctx := latency.Context(context.Background())
	return latency.MeasureConfig(ctx, configContent, link, time.Duration(timeoutMillis)*time.Millisecond)
}
