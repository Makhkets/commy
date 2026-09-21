package config

import (
	"bytes"
	"encoding/json"
	"os"
	"testing"
)

// The app writes the transport block in Dart; this package reads it in Go. The
// fixture is what the Dart builder emits for a set of real-looking links — its
// own test holds it to that — so decoding it here, as strictly as the core
// does, is the check that the two halves still agree.
func TestTheAppWritesBlocksTheCoreAccepts(t *testing.T) {
	raw, err := os.ReadFile("testdata/dart_blocks.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Cases []struct {
			Name      string          `json:"name"`
			Transport json.RawMessage `json:"transport"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Cases) == 0 {
		t.Fatal("the fixture holds no cases")
	}
	for _, c := range fixture.Cases {
		var block map[string]json.RawMessage
		if err := json.Unmarshal(c.Transport, &block); err != nil {
			t.Fatalf("%s: %v", c.Name, err)
		}
		if string(block["type"]) != `"`+TransportType+`"` {
			t.Errorf("%s: type is %s", c.Name, block["type"])
		}
		// sing-box strips `type` before it hands the rest to the options.
		delete(block, "type")
		rest, err := json.Marshal(block)
		if err != nil {
			t.Fatal(err)
		}
		var options Options
		decoder := json.NewDecoder(bytes.NewReader(rest))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&options); err != nil {
			t.Errorf("%s: the core would refuse this block: %v", c.Name, err)
			continue
		}
		if _, err := options.Resolve(); err != nil {
			t.Errorf("%s: the core would refuse this block: %v", c.Name, err)
		}
	}
}
