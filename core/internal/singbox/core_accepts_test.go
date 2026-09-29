//go:build commy_overlay

package singbox_test

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// The Go half of packages/commy_config/test/builder/core_accepts_contract_test.dart.
//
// A value the app's builder writes and sing-box refuses stops the whole core,
// every server with it: outbounds are constructed when the box is created, and
// the first one that fails fails the box. The fixture is what the builder
// writes for links whose values used to reach the core as they were — a VLESS
// flow only Xray knows, a plugin under another name, a single-port hop, a bare
// WireGuard address, a direct resolver given by name, routing rules as users
// and other clients type them. Each one is constructed here, by the library
// itself.
//
// Run with the build tags, like the other tests in this package:
//
//	go test -modfile="$(go run ./cmd/overlaygen)" \
//	    -tags "<core tags>,commy_overlay" ./internal/singbox/
func TestTheCoreConstructsWhatTheAppWrites(t *testing.T) {
	raw, err := os.ReadFile("testdata/dart_nodes.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Cases []struct {
			Name   string          `json:"name"`
			Kind   string          `json:"kind"`
			Object json.RawMessage `json:"object"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Cases) == 0 {
		t.Fatal("the fixture holds no cases")
	}
	for _, c := range fixture.Cases {
		t.Run(c.Name, func(t *testing.T) {
			var document string
			switch c.Kind {
			case "outbound":
				document = `{"log": {"disabled": true}, "outbounds": [` + string(c.Object) + `]}`
			case "endpoint":
				document = `{"log": {"disabled": true}, "endpoints": [` + string(c.Object) + `]}`
			case "inbound":
				document = `{"log": {"disabled": true}, "inbounds": [` + string(c.Object) + `]}`
			case "dns":
				// The section refers to the proxy group by its tag.
				document = `{"log": {"disabled": true}, "dns": ` + string(c.Object) +
					`, "outbounds": [{"type": "direct", "tag": "proxy"}]}`
			case "route":
				// The rules name the proxy group, the direct outbound and the
				// two resolvers by their tags.
				document = `{"log": {"disabled": true}, "dns": {"servers": [` +
					`{"type": "local", "tag": "dns-remote"}, {"type": "local", "tag": "dns-direct"}]}` +
					`, "route": ` + string(c.Object) +
					`, "outbounds": [{"type": "direct", "tag": "proxy"}, {"type": "direct", "tag": "direct"}]}`
			default:
				t.Fatalf("unknown kind %q", c.Kind)
			}

			ctx, cancel := context.WithCancel(include.Context(context.Background()))
			defer cancel()
			options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(document))
			if err != nil {
				t.Fatalf("the core would not decode it: %v", err)
			}
			instance, err := box.New(box.Options{Context: ctx, Options: options})
			if err != nil {
				t.Fatalf("the core would not construct it: %v", err)
			}
			if err := instance.Close(); err != nil {
				t.Logf("close: %v", err)
			}
		})
	}
}
