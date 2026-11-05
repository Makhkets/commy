import Flutter
import Libbox
import NetworkExtension
import UIKit

final class CoreBridge: NSObject {
  private let worker = DispatchQueue(label: "dev.commy.app.core")
  private var manager: NETunnelProviderManager?
  private var client: LibboxCommandClient?
  private let events = CoreEvents()
  private var streams: [String: CoreStream] = [:]
  private var statusObserver: NSObjectProtocol?
  private var activeObserver: NSObjectProtocol?
  private var requestedStop = false
  private var lastStatus: NEVPNStatus = .invalid
  private var starting = false
  private var startGeneration = 0
  private var locale = ""
  private var providerID: String { Bundle.main.bundleIdentifier! + ".CommyTunnel" }

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    for name in ["status", "traffic", "logs", "connections", "intents"] {
      let stream = CoreStream(
        buffer: name == "intents" || name == "logs",
        initial: name == "status"
          ? SharedCore.json(["state": "idle"]) : name == "connections" ? "[]" : nil)
      streams[name] = stream
      FlutterEventChannel(name: "dev.commy.app/\(name)", binaryMessenger: messenger)
        .setStreamHandler(stream)
    }
    events.emit = { [weak self] name, value in self?.emit(name, value) }
    FlutterMethodChannel(name: "dev.commy.app/core", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: nil, queue: .main
    ) { [weak self] _ in self?.statusChanged() }
    activeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.restore() }
    restore()
  }
  deinit {
    if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
  }
  private func emit(_ name: String, _ value: Any) {
    let json = SharedCore.json(value)
    DispatchQueue.main.async { [weak self] in self?.streams[name]?.send(json) }
  }
  private func log(_ message: String, level: String = "info") {
    emit("logs", ["level": level, "message": message, "tag": "core.ios", "at": SharedCore.now])
  }
  func receive(_ url: URL) {
    guard url.isFileURL else {
      emit("intents", ["kind": "link", "uri": url.absoluteString])
      return
    }
    worker.async {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      do {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximum = 4 * 1024 * 1024
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum, let text = String(data: data, encoding: .utf8) else {
          throw SharedCore.failure("Import requires a UTF-8 file up to 4 MiB")
        }
        self.emit("intents", ["kind": "text", "text": text])
      } catch {
        self.log("File import failed: \(error.localizedDescription)", level: "error")
        self.emit("intents", ["kind": "file"])
      }
    }
  }
  private func restore() {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      guard let self else { return }
      DispatchQueue.main.async {
        if let error {
          self.log("Loading VPN profile failed: \(error.localizedDescription)", level: "error")
        }
        self.manager = managers?.first {
          ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
            == self.providerID
        }
        self.statusChanged()
      }
    }
  }
  private func statusChanged() {
    let status = manager?.connection.status ?? .disconnected
    let wasActive = [.connected, .connecting, .reasserting].contains(lastStatus)
    lastStatus = status
    let state: String
    switch status {
    case .connected: state = "connected"
    case .connecting, .reasserting: state = "starting"
    case .disconnecting: state = "stopping"
    default: state = "idle"
    }
    var value: [String: Any] = ["state": state]
    if let since = manager?.connection.connectedDate {
      value["since"] = Int64(since.timeIntervalSince1970 * 1000)
    }
    if state == "idle", wasActive, !requestedStop {
      value = [
        "state": "error", "code": "core_crashed",
        "reason": (try? SharedCore.read("last-error"))
          ?? "VPN stopped unexpectedly; inspect iOS VPN diagnostics",
      ]
    }
    emit("status", value)
    log("VPN state: \(state)")
    if status == .connected {
      worker.async { [weak self] in
        guard let self, self.client == nil else { return }
        do {
          try SharedCore.setup()
          let options = LibboxCommandClientOptions()
          options.statusInterval = 1_000_000_000
          for command in [
            LibboxCommandStatus, LibboxCommandLog, LibboxCommandGroup, LibboxCommandConnections,
          ] { options.addCommand(command) }
          let client = LibboxNewCommandClient(self.events, options)!
          try client.connect()
          self.client = client
        } catch {
          self.log(
            "Core diagnostics connection failed: \(error.localizedDescription)", level: "error")
        }
      }
    } else if status == .disconnected || status == .invalid {
      worker.async { [weak self] in
        try? self?.client?.disconnect()
        self?.client = nil
      }
      emit("connections", [])
    }
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard !starting else {
        result(
          FlutterError(code: "already_running", message: "VPN start in progress", details: nil))
        return
      }
      guard let config = call.arguments as? String else {
        invalid(result)
        return
      }
      if let status = manager?.connection.status,
        [.connected, .connecting, .reasserting].contains(status)
      {
        result(FlutterError(code: "already_running", message: "VPN is active", details: nil))
        return
      }
      starting = true
      startGeneration += 1
      let generation = startGeneration
      Task { @MainActor in
        defer { starting = false }
        do {
          if manager == nil {
            let profiles = try await NETunnelProviderManager.loadAllFromPreferences()
            manager =
              profiles.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                  == providerID
              } ?? NETunnelProviderManager()
          }
          guard let manager else { throw SharedCore.failure("Missing VPN profile") }
          if (try? SharedCore.read("command-secret")) == nil {
            try SharedCore.save("command-secret", UUID().uuidString)
          }
          try SharedCore.save("config", SharedCore.prepare(config))
          SharedCore.remove("last-error")
          let proto = NETunnelProviderProtocol()
          proto.providerBundleIdentifier = providerID
          proto.serverAddress = "Commy"
          proto.disconnectOnSleep = false
          // Secrets are only in the shared Keychain.
          manager.protocolConfiguration = proto
          manager.localizedDescription = "Commy"
          manager.isEnabled = true
          try await manager.saveToPreferences()
          try await manager.loadFromPreferences()
          guard generation == startGeneration else {
            result(nil)
            return
          }
          requestedStop = false
          try (manager.connection as! NETunnelProviderSession).startTunnel()
          statusChanged()
          result(nil)
        } catch { fail("start", error, result) }
      }
    case "stop":
      startGeneration += 1
      requestedStop = true
      manager?.isOnDemandEnabled = false
      manager?.connection.stopVPNTunnel()
      result(nil)
    case "version": result(LibboxVersion())
    case "deviceInfo":
      result(
        SharedCore.json([
          "os": "iOS", "osVersion": UIDevice.current.systemVersion, "model": UIDevice.current.model,
        ]))
    case "setLocale":
      locale = call.arguments as? String ?? ""
      result(nil)
    case "appLocale": result("")
    case "installedApps": result("[]")
    case "setStartOnBoot":
      result(
        FlutterError(
          code: "unsupported", message: "iOS does not provide an app boot receiver", details: nil))
    case "openVpnSettings":
      UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
      result(nil)
    case "ping": result("{\"delayMs\":null}")
    case "proxies": result(SharedCore.json(events.groups))
    case "reload", "select", "urlTest", "probeOutbounds":
      worker.async { [weak self] in
        guard let self else { return }
        do {
          var answer: Any?
          switch call.method {
          case "reload":
            guard let client = self.client else {
              throw SharedCore.failure("Tunnel diagnostics are not connected")
            }
            guard let config = call.arguments as? String else {
              throw SharedCore.failure("Missing configuration")
            }
            try SharedCore.save("config", SharedCore.prepare(config))
            try client.serviceReload()
            try? client.disconnect()
            self.client = nil
            DispatchQueue.main.async { self.statusChanged() }
          case "select":
            let args = try SharedCore.object(call.arguments as? String)
            guard let client = self.client, let group = args["group"] as? String,
              let tag = args["tag"] as? String
            else { throw SharedCore.failure("Missing selector or running tunnel") }
            try client.selectOutbound(group, outboundTag: tag)
          default:
            let args = try SharedCore.object(call.arguments as? String)
            let config: String
            if call.method == "probeOutbounds" {
              guard let provided = args["config"] as? String else {
                throw SharedCore.failure("Missing probe configuration")
              }
              config = provided
            } else {
              // Probe exactly the requested outbound and URL; libbox's group URLTest ignores URL.
              let saved = try SharedCore.object(SharedCore.read("config"))
              guard args["tag"] is String else { throw SharedCore.failure("Missing outbound tag") }
              var probe: [String: Any] = ["log": ["disabled": true]]
              for key in ["outbounds", "endpoints", "dns"] { probe[key] = saved[key] }
              config = SharedCore.json(probe)
            }
            guard let url = args["url"] as? String else {
              throw SharedCore.failure("Missing probe URL")
            }
            let timeout = Int32(clamping: args["timeoutMs"] as? Int ?? 5000)
            var error: NSError?
            let raw =
              call.method == "urlTest"
              ? MobileURLTestOutbound(config, args["tag"] as? String, url, timeout, &error)
              : MobileURLTestOutboundsDetailed(config, url, timeout, &error)
            if let error { throw error }
            if call.method == "urlTest" {
              let measured = try SharedCore.object(raw)
              let value = measured[args["tag"] as? String ?? ""] as? [String: Any]
              if let reason = value?["error"] as? String {
                self.log("Proxy GET failed: \(reason)", level: "warn")
              }
              let delay = value?["delay"] as? Int ?? 0
              answer = SharedCore.json(["delayMs": delay > 0 ? delay as Any : NSNull()])
            } else {
              answer = raw
            }
          }
          DispatchQueue.main.async { result(answer) }
        } catch { DispatchQueue.main.async { self.fail(call.method, error, result) } }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func invalid(_ result: FlutterResult) {
    result(
      FlutterError(code: "config_invalid", message: "Expected configuration JSON", details: nil))
  }
  private func fail(_ method: String, _ error: Error, _ result: FlutterResult) {
    log("\(method) failed: \(error.localizedDescription)", level: "error")
    let code =
      (error as NSError).domain == NEVPNErrorDomain
        && (error as NSError).code == NEVPNError.configurationReadWriteFailed.rawValue
      ? "permission_denied" : "config_invalid"
    result(FlutterError(code: code, message: error.localizedDescription, details: nil))
  }
}

private final class CoreStream: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var latest: String?
  private let retainsLatest: Bool
  private let buffers: Bool
  private var pending: [String] = []
  init(buffer: Bool = false, initial: String?) {
    latest = initial
    retainsLatest = initial != nil
    buffers = buffer
  }
  func send(_ value: String) {
    if retainsLatest { latest = value }
    if let sink { sink(value) } else if buffers { pending = Array((pending + [value]).suffix(100)) }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    if let latest { events(latest) }
    for value in pending { events(value) }
    pending.removeAll()
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
