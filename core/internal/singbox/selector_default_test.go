//go:build commy_overlay

package singbox_test

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/protocol/group"
	"github.com/sagernet/sing/common/json"
)

// This test needs the build overlay, for the same reason as the others here:
//
//	GODEBUG=goindex=0 go test -overlay="$(go run ./cmd/overlaygen)" \
//	    -tags "<core tags>,commy_overlay" ./internal/singbox/
//
// With the cache file on, sing-box starts a selector on whatever was last
// selected inside a running core and reads the configured default only when
// the cache is empty. Commy puts the user's choice into that default on every
// start, so a server picked while disconnected lost to the one switched to in
// the previous session — the chip named one server, the traffic went through
// another.
func TestSelectorStartsOnItsDefaultNotOnTheCache(t *testing.T) {
	cache := filepath.Join(t.TempDir(), "cache.db")

	// Session one starts on a and is switched to b inside the running core,
	// which is the moment the cache file records b.
	if now := runSelector(t, cache, "a", "b"); now != "b" {
		t.Fatalf("the switch inside the core did not take: on %q", now)
	}

	// The user picks a again while no core runs; the app writes it into the
	// configuration as the default, as it does on every start.
	if now := runSelector(t, cache, "a", ""); now != "a" {
		t.Fatalf("the selector started on %q; the configuration said %q", now, "a")
	}
}

// runSelector starts a core whose selector defaults to [defaultTag], switches
// it to [switchTo] when that is not empty, and returns where it ended up.
func runSelector(t *testing.T, cache, defaultTag, switchTo string) string {
	t.Helper()
	document := fmt.Sprintf(`{
		"log": {"disabled": true},
		"outbounds": [
			{"type": "direct", "tag": "a"},
			{"type": "direct", "tag": "b"},
			{"type": "selector", "tag": "proxy", "outbounds": ["a", "b"], "default": %q}
		],
		"experimental": {"cache_file": {"enabled": true, "path": %q}}
	}`, defaultTag, cache)

	ctx := include.Context(context.Background())
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(document))
	if err != nil {
		t.Fatal(err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		t.Fatalf("box.New: %v", err)
	}
	if err := instance.Start(); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer instance.Close()

	outbound, loaded := instance.Outbound().Outbound("proxy")
	if !loaded {
		t.Fatal("no selector in the running core")
	}
	selector, ok := outbound.(*group.Selector)
	if !ok {
		t.Fatalf("proxy is a %T", outbound)
	}
	if switchTo != "" && !selector.SelectOutbound(switchTo) {
		t.Fatalf("could not switch to %q", switchTo)
	}
	return selector.Now()
}
