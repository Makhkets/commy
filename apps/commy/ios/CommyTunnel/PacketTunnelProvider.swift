import NetworkExtension
import Libbox

final class PacketTunnelProvider: NEPacketTunnelProvider, LibboxCommandServerHandlerProtocol {
    private let worker = DispatchQueue(label: "dev.commy.tunnel.lifecycle")
    private var server: LibboxCommandServer?
    private var platform: TunnelPlatform?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        worker.async {
            do {
                try SharedCore.setup()
                let platform = TunnelPlatform(provider: self)
                self.platform = platform
                var error: NSError?
                guard let server = LibboxNewCommandServer(self, platform, &error) else {
                    throw error ?? SharedCore.failure("Could not create the tunnel core")
                }
                self.server = server
                try server.start()
                try server.startOrReloadService(SharedCore.read("config"), options: LibboxOverrideOptions())
                completionHandler(nil)
            } catch {
                try? SharedCore.save("last-error", error.localizedDescription)
                self.platform?.stopMonitor()
                self.server?.close()
                self.server = nil
                self.platform = nil
                completionHandler(error)
            }
        }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        worker.async {
            try? self.server?.closeService()
            self.server?.close()
            self.server = nil
            self.platform?.stopMonitor()
            self.platform = nil
            completionHandler()
        }
    }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        worker.async {
            do {
                guard String(data: messageData, encoding: .utf8) == "reload" else {
                    throw SharedCore.failure("Unknown tunnel command")
                }
                guard let server = self.server else { throw SharedCore.failure("Tunnel is not running") }
                try server.startOrReloadService(SharedCore.read("config"), options: LibboxOverrideOptions())
                completionHandler?(Data("{}".utf8))
            } catch {
                completionHandler?(Data(SharedCore.json(["error": error.localizedDescription]).utf8))
            }
        }
    }
    func serviceStop() throws { cancelTunnelWithError(nil) }
    func serviceReload() throws {
        try server?.startOrReloadService(SharedCore.read("config"), options: LibboxOverrideOptions())
    }
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus { LibboxSystemProxyStatus() }
    func setSystemProxyEnabled(_ enabled: Bool) throws {}
    func writeDebugMessage(_ message: String?) {
        // Raw core debug messages can carry credentials. They are never sent to OS logs.
    }
}
