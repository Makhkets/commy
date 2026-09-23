//go:build commy_overlay && linux && with_gvisor

package singtun_test

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"syscall"
	"testing"
	"time"

	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// This test needs the build overlay, because the defect is in sing-tun:
//
//	GODEBUG=goindex=0 go test -overlay="$(go run ./cmd/overlaygen)" \
//	    -tags "<core tags>,commy_overlay" ./internal/singtun/
//
// A closed gVisor stack has to stop reading its device. Without the edit it
// did not: the reader stayed asleep on the descriptor and took the first
// packet that arrived after the stack was gone. On Android that is one TUN
// interface left behind per reconnect, and a reader that, once woken, reads
// whatever file has inherited the descriptor number.
//
// A socket pair stands in for the TUN device — fdbased reads both the same
// way — so the test needs neither root nor /dev/net/tun. One end is the
// stack's; the other plays the kernel, writing what an app sent into the
// tunnel.
func TestClosedGVisorStackStopsReadingTheDevice(t *testing.T) {
	pair, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_SEQPACKET|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	device, kernel := pair[0], pair[1]
	t.Cleanup(func() { _ = syscall.Close(kernel) })

	options := tun.Options{
		FileDescriptor: device,
		MTU:            1500,
		Inet4Address:   []netip.Prefix{netip.MustParsePrefix("172.19.0.1/30")},
		// Nothing to undo on Close but the descriptor: this test configured no
		// address and no route, and has no right to.
		EXP_ExternalConfiguration: true,
	}
	nic, err := tun.New(options)
	if err != nil {
		t.Fatal(err)
	}
	// The device end belongs to nic from here on; closing it through nic keeps
	// the file's finalizer from closing the number a second time.
	t.Cleanup(func() { _ = nic.Close() })

	stack, err := tun.NewStack("gvisor", tun.StackOptions{
		Context:    context.Background(),
		Tun:        nic,
		TunOptions: options,
		UDPTimeout: time.Minute,
		Handler:    refuseAll{},
		Logger:     logger.NOP(),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := stack.Start(); err != nil {
		t.Fatal(err)
	}
	if err := stack.Close(); err != nil {
		t.Fatal(err)
	}

	// What the packet holds does not matter: a reader that still runs takes it
	// off the socket either way. This one is an empty IPv4 datagram.
	packet := []byte{
		0x45, 0, 0, 20, 0, 0, 0, 0, 64, 17, 0, 0,
		172, 19, 0, 2, 172, 19, 0, 1,
	}
	if _, err := syscall.Write(kernel, packet); err != nil {
		t.Fatal(err)
	}
	time.Sleep(200 * time.Millisecond)

	// fdbased made the descriptor non-blocking, so an empty socket answers
	// EAGAIN instead of hanging the test.
	buffer := make([]byte, 2048)
	n, err := syscall.Read(device, buffer)
	if errors.Is(err, syscall.EAGAIN) {
		t.Fatal("the closed stack still reads the device: its reader took the packet written after Close")
	}
	if err != nil {
		t.Fatal(err)
	}
	if n != len(packet) {
		t.Fatalf("read back %d bytes, wrote %d", n, len(packet))
	}
}

// refuseAll handles a stack that is never meant to carry a connection.
type refuseAll struct{}

func (refuseAll) PrepareConnection(
	string, M.Socksaddr, M.Socksaddr, tun.DirectRouteContext, time.Duration,
) (tun.DirectRouteDestination, error) {
	return nil, errors.New("refused")
}

func (refuseAll) NewConnectionEx(
	_ context.Context, conn net.Conn, _, _ M.Socksaddr, onClose N.CloseHandlerFunc,
) {
	_ = conn.Close()
	if onClose != nil {
		onClose(nil)
	}
}

func (refuseAll) NewPacketConnectionEx(
	_ context.Context, conn N.PacketConn, _, _ M.Socksaddr, onClose N.CloseHandlerFunc,
) {
	_ = conn.Close()
	if onClose != nil {
		onClose(nil)
	}
}
