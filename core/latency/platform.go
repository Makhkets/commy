package latency

import (
	"net/netip"
	"os"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
)

// probePlatform is the platform a probe instance runs on: none, said
// explicitly.
//
// With no platform at all, sing-box on Android reaches for what an app may not
// touch — a netlink socket to watch the routes, the system package list — and
// the instance fails to start. libbox's own stand-in (for checkConfig) is
// built for an instance that is never started: its interface monitor refuses
// to start. This one starts, watches nothing and binds nothing.
//
// Binding nothing is the point. A probe instance has no TUN of its own, and
// the app's process is excluded from Commy's tunnel when one is up, so its
// sockets go out over whatever network the device is on — exactly where the
// tunnel's own connections to the server go.
type probePlatform struct{}

var _ adapter.PlatformInterface = probePlatform{}

func (probePlatform) Initialize(adapter.NetworkManager) error { return nil }

func (probePlatform) UsePlatformAutoDetectInterfaceControl() bool { return true }

func (probePlatform) AutoDetectInterfaceControl(int) error { return nil }

func (probePlatform) UsePlatformInterface() bool { return false }

func (probePlatform) OpenInterface(*tun.Options, option.TunPlatformOptions) (tun.Tun, error) {
	return nil, os.ErrInvalid
}

func (probePlatform) UsePlatformDefaultInterfaceMonitor() bool { return true }

func (probePlatform) CreateDefaultInterfaceMonitor(logger.Logger) tun.DefaultInterfaceMonitor {
	return probeMonitor{}
}

// An empty list, not an error: sing-box asks when an interface changes, and
// nothing here ever reports one.
func (probePlatform) UsePlatformNetworkInterfaces() bool { return true }

func (probePlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) { return nil, nil }

func (probePlatform) UnderNetworkExtension() bool { return false }

func (probePlatform) NetworkExtensionIncludeAllNetworks() bool { return false }

func (probePlatform) ClearDNSCache() {}

func (probePlatform) RequestPermissionForWIFIState() error { return nil }

func (probePlatform) ReadWIFIState() adapter.WIFIState { return adapter.WIFIState{} }

// None, so sing-box loads the system's roots itself — what the tunnel's
// platform on Android answers too.
func (probePlatform) SystemCertificates() []string { return nil }

func (probePlatform) UsePlatformConnectionOwnerFinder() bool { return false }

func (probePlatform) FindConnectionOwner(*adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, os.ErrInvalid
}

func (probePlatform) UsePlatformWIFIMonitor() bool { return false }

func (probePlatform) UsePlatformNotification() bool { return false }

func (probePlatform) SendNotification(*adapter.Notification) error { return nil }

func (probePlatform) MyInterfaceAddress() []netip.Addr { return nil }

// probeMonitor reports no default interface and never changes its mind.
type probeMonitor struct{}

var _ tun.DefaultInterfaceMonitor = probeMonitor{}

func (probeMonitor) Start() error { return nil }

func (probeMonitor) Close() error { return nil }

func (probeMonitor) DefaultInterface() *control.Interface { return nil }

func (probeMonitor) OverrideAndroidVPN() bool { return false }

func (probeMonitor) AndroidVPNEnabled() bool { return false }

func (probeMonitor) RegisterCallback(tun.DefaultInterfaceUpdateCallback) *list.Element[tun.DefaultInterfaceUpdateCallback] {
	return nil
}

func (probeMonitor) UnregisterCallback(*list.Element[tun.DefaultInterfaceUpdateCallback]) {}

func (probeMonitor) RegisterMyInterface(string) {}

func (probeMonitor) MyInterfaces() []string { return nil }
