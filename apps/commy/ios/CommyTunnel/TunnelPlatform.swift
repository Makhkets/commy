import Foundation
import Network
import NetworkExtension
import Libbox
import Darwin

final class TunnelPlatform: NSObject, LibboxPlatformInterfaceProtocol {
    private weak var provider: NEPacketTunnelProvider?
    private var monitor: NWPathMonitor?
    private let pathLock = NSLock()
    private var currentPath: Network.NWPath?
    private let monitorQueue = DispatchQueue(label: "dev.commy.tunnel.path")
    init(provider: NEPacketTunnelProvider) { self.provider = provider }

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let provider, let ret0_ else { throw SharedCore.failure("Missing TUN options") }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())
        let v4 = prefixes(options.getInet4Address())
        if !v4.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: v4.map { $0.address() }, subnetMasks: v4.map { $0.mask() })
            ipv4.includedRoutes = options.getAutoRoute() ? [NEIPv4Route.default()] : prefixes(options.getInet4RouteAddress()).map { NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask()) }
            ipv4.excludedRoutes = prefixes(options.getInet4RouteExcludeAddress()).map { NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask()) }
            settings.ipv4Settings = ipv4
        }
        let v6 = prefixes(options.getInet6Address())
        if !v6.isEmpty {
            let ipv6 = NEIPv6Settings(addresses: v6.map { $0.address() }, networkPrefixLengths: v6.map { NSNumber(value: $0.prefix()) })
            ipv6.includedRoutes = options.getAutoRoute() ? [NEIPv6Route.default()] : prefixes(options.getInet6RouteAddress()).map { NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix())) }
            ipv6.excludedRoutes = prefixes(options.getInet6RouteExcludeAddress()).map { NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix())) }
            settings.ipv6Settings = ipv6
        }
        let dns = try options.getDNSServerAddress()
        let dnsSettings = NEDNSSettings(servers: [dns.value])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings
        let ready = DispatchSemaphore(value: 0)
        var settingsError: Error?
        provider.setTunnelNetworkSettings(settings) { error in
            settingsError = error
            ready.signal()
        }
        guard ready.wait(timeout: .now() + 15) == .success else { throw SharedCore.failure("Applying VPN routes and DNS timed out") }
        if let settingsError { throw settingsError }
        // Public socket operations in libbox; no private KVC on packetFlow.
        let fd = LibboxGetTunnelFileDescriptor()
        guard fd >= 0 else { throw SharedCore.failure("iOS did not expose a utun file descriptor") }
        ret0_.pointee = fd
    }
    private func prefixes(_ iterator: LibboxRoutePrefixIteratorProtocol?) -> [LibboxRoutePrefix] {
        var values: [LibboxRoutePrefix] = []
        while let iterator, iterator.hasNext() { if let value = iterator.next() { values.append(value) } }
        return values
    }
    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        stopMonitor()
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let initial = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.pathLock.lock(); self?.currentPath = path; self?.pathLock.unlock()
            let interface = path.availableInterfaces.first { path.usesInterfaceType($0.type) }
            defer { initial.signal() }
            listener?.updateDefaultInterface(interface?.name ?? "", interfaceIndex: Int32(interface?.index ?? 0), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
        }
        monitor.start(queue: monitorQueue)
        guard initial.wait(timeout: .now() + 5) == .success else { throw SharedCore.failure("Network interface discovery timed out") }
    }
    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws { stopMonitor() }
    func stopMonitor() { monitor?.cancel(); monitor = nil }
    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        pathLock.lock(); let path = currentPath; pathLock.unlock()
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { throw SharedCore.failure("Could not enumerate network interfaces") }
        defer { freeifaddrs(first) }
        var addresses: [String: [String]] = [:]
        var flags: [String: UInt32] = [:]
        var cursor = first
        while let ptr = cursor {
            let entry = ptr.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr, let mask = entry.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else { continue }
            let name = String(cString: entry.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes: [UInt8]
            if address.pointee.sa_family == UInt8(AF_INET) {
                bytes = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p in withUnsafeBytes(of: p.pointee.sin_addr) { Array($0) } }
            } else {
                bytes = mask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p in withUnsafeBytes(of: p.pointee.sin6_addr) { Array($0) } }
            }
            let prefix = bytes.reduce(0) { $0 + $1.nonzeroBitCount }
            let ip = String(cString: host).components(separatedBy: "%")[0]
            addresses[name, default: []].append("\(ip)/\(prefix)")
            flags[name] = entry.ifa_flags
        }
        let values = addresses.map { name, ips -> LibboxNetworkInterface in
            let value = LibboxNetworkInterface()
            value.name = name
            value.index = Int32(if_nametoindex(name))
            value.mtu = 1500
            value.addresses = StringIterator(ips)
            // libbox uses Go net.Flags, whose bits differ from BSD IFF_*.
            let f = flags[name] ?? 0
            value.flags = (f & UInt32(IFF_UP) != 0 ? 1 : 0) | (f & UInt32(IFF_BROADCAST) != 0 ? 2 : 0) | (f & UInt32(IFF_LOOPBACK) != 0 ? 4 : 0) | (f & UInt32(IFF_POINTOPOINT) != 0 ? 8 : 0) | (f & UInt32(IFF_MULTICAST) != 0 ? 16 : 0)
            let type = path?.availableInterfaces.first { $0.name == name }?.type
            value.type = type == .wifi ? LibboxInterfaceTypeWIFI : type == .cellular ? LibboxInterfaceTypeCellular : LibboxInterfaceTypeEthernet
            value.metered = type == .cellular
            return value
        }
        return InterfaceIterator(values)
    }
    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }
    func usePlatformAutoDetectControl() -> Bool { false }
    func autoDetectControl(_ fd: Int32) throws {}
    func useProcFS() -> Bool { false }
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func systemCertificates() -> LibboxStringIteratorProtocol? { nil }
    func clearDNSCache() {}
    func send(_ notification: LibboxNotification?) throws {}
    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw SharedCore.failure("Per-app routing is unavailable on iOS")
    }
}

private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var values: [LibboxNetworkInterface]
    private var index = 0
    init(_ values: [LibboxNetworkInterface]) { self.values = values }
    func hasNext() -> Bool { index < values.count }
    func next() -> LibboxNetworkInterface? { guard hasNext() else { return nil }; defer { index += 1 }; return values[index] }
}
private final class StringIterator: NSObject, LibboxStringIteratorProtocol {
    private var values: [String]
    private var index = 0
    init(_ values: [String]) { self.values = values }
    func hasNext() -> Bool { index < values.count }
    func next() -> String { guard hasNext() else { return "" }; defer { index += 1 }; return values[index] }
    func len() -> Int32 { Int32(values.count - index) }
}
