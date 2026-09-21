// Command devbox runs the pinned core on a desktop with a configuration file,
// and nothing else: no TUN, no platform interface, no app.
//
//	OVERLAY=$(go run ./cmd/overlaygen)
//	GODEBUG=goindex=0 go build -overlay="$OVERLAY" -tags "<core tags>" \
//	    -ldflags "-checklinkname=0" -o build/devbox ./cmd/devbox
//	build/devbox config.json
//
// It exists because three sessions in a row needed one and built it from
// memory: to prove the tunnel carries traffic against a live server, to run the
// leak checklist, and to test a transport against a real Xray
// (scripts/xhttp_interop.sh). A developer tool — it is not part of any
// artefact the app ships.
//
// Built without the overlay it still runs, as plain upstream sing-box: it will
// refuse an xhttp transport by name, which is a quick way to see what the
// overlay adds.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: devbox <config.json>")
		os.Exit(2)
	}
	if err := run(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, "devbox:", err)
		os.Exit(1)
	}
}

func run(path string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	ctx := include.Context(context.Background())
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, content)
	if err != nil {
		return fmt.Errorf("decode config: %w", err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return fmt.Errorf("create: %w", err)
	}
	// libbox does this for the app; without it the package-level logger that
	// transports write to never reaches the instance's log.
	log.SetStdLogger(instance.LogFactory().Logger())
	if err := instance.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	<-signals
	return instance.Close()
}
