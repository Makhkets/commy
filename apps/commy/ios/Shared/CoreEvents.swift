import Foundation
import Libbox

// One client per process. libbox invokes these callbacks off the main thread.
final class CoreEvents: NSObject, LibboxCommandClientHandlerProtocol {
    var emit: (String, Any) -> Void = { _, _ in }
    private let lock = NSLock()
    private var groupSnapshot: [[String: Any]] = []
    private let connections = LibboxNewConnections()!
    var groups: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return groupSnapshot
    }
    func connected() {}
    func disconnected(_ message: String?) {
        if let message, !message.isEmpty {
            emit("logs", ["level": "warn", "tag": "core.ios", "message": message, "at": SharedCore.now])
        }
    }
    func clearLogs() {}
    func setDefaultLogLevel(_ level: Int32) {}
    func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
    func updateClashMode(_ newMode: String?) {}
    func writeStatus(_ message: LibboxStatusMessage?) {
        guard let m = message, m.trafficAvailable else { return }
        emit("traffic", ["up": m.uplink, "down": m.downlink, "upTotal": m.uplinkTotal,
                         "downTotal": m.downlinkTotal, "at": SharedCore.now])
    }
    func writeLogs(_ messageList: LibboxLogIteratorProtocol?) {
        var lines: [[String: Any]] = []
        let levels = [0: "trace", 1: "debug", 2: "info", 3: "warn", 4: "error", 5: "fatal", 6: "fatal"]
        while let messageList, messageList.hasNext() {
            guard let line = messageList.next() else { continue }
            lines.append(["level": levels[Int(line.level)] ?? "info", "message": line.message,
                          "tag": "core.ios", "at": SharedCore.now])
        }
        // Only passed in memory to Dart's redactor, never to NSLog or a file.
        if !lines.isEmpty { emit("logs", lines) }
    }
    func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {
        var groups: [[String: Any]] = []
        while let message, message.hasNext() {
            guard let group = message.next() else { continue }
            var items: [[String: Any]] = []
            let iterator = group.getItems()
            while let iterator, iterator.hasNext() {
                guard let item = iterator.next() else { continue }
                items.append(["tag": item.tag, "type": item.type, "urlTestDelay": item.urlTestDelay])
            }
            groups.append(["tag": group.tag, "type": group.type, "selected": group.selected,
                           "selectable": group.selectable, "items": items])
        }
        lock.lock(); groupSnapshot = groups; lock.unlock()
    }
    func write(_ events: LibboxConnectionEvents?) {
        lock.lock()
        connections.apply(events)
        connections.filterState(Int32(LibboxConnectionStateActive))
        var values: [[String: Any]] = []
        let iterator = connections.iterator()
        while let iterator, iterator.hasNext() {
            guard let c = iterator.next() else { continue }
            values.append(["id": c.id_, "host": c.displayDestination(), "rule": c.rule,
                           "outbound": c.outbound, "up": c.uplinkTotal, "down": c.downlinkTotal,
                           "start": c.createdAt, "network": c.network])
        }
        lock.unlock()
        emit("connections", values)
    }
}
