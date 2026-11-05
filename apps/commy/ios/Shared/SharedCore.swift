import Foundation
import Security
import Libbox
import CryptoKit

// Secrets never go in providerConfiguration, UserDefaults or plaintext files.
enum SharedCore {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "CommyAppGroup") as! String }
    static var keychainGroup: String { Bundle.main.object(forInfoDictionaryKey: "CommyKeychainGroup") as! String }
    static var directory: URL {
        get throws {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw failure("App Group unavailable; check both provisioning profiles")
            }
            return url
        }
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "dev.commy.app", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.commy.app.tunnel",
         kSecAttrAccount as String: key,
         kSecAttrAccessGroup as String: keychainGroup]
    }
    static func save(_ key: String, _ value: String) throws {
        let item = query(key)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(item as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(item.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure("Keychain write failed (\(status))") }
    }
    static func read(_ key: String) throws -> String {
        var item = query(key)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw failure("Keychain read failed (\(status)); unlock the device once after reboot")
        }
        return value
    }
    static func remove(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
    // Rule sets are public data; their private app paths are not accessible to the extension.
    static func prepare(_ content: String) throws -> String {
        var config = try object(content)
        if var route = config["route"] as? [String: Any], var sets = route["rule_set"] as? [[String: Any]] {
            let root = try directory.appendingPathComponent("rules", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for index in sets.indices {
                guard let path = sets[index]["path"] as? String else { continue }
                let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
                let name = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let dest = root.appendingPathComponent(name + ".srs")
                if !FileManager.default.fileExists(atPath: dest.path) { try bytes.write(to: dest, options: .atomic) }
                sets[index]["path"] = dest.path
            }
            route["rule_set"] = sets
            config["route"] = route
        }
        return json(config)
    }
    static func setup() throws {
        let root = try directory
        for name in ["core", "tmp"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var excludedRoot = root
        try excludedRoot.setResourceValues(resourceValues)
        let options = LibboxSetupOptions()
        options.basePath = root.path
        options.workingPath = root.appendingPathComponent("core").path
        options.tempPath = root.appendingPathComponent("tmp").path
        options.logMaxLines = 300
        options.debug = false
        options.commandServerSecret = try read("command-secret")
        var error: NSError?
        LibboxSetup(options, &error)
        if let error { throw error }
        LibboxSetMemoryLimit(true)
    }
    static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
    static func object(_ text: String?) throws -> [String: Any] {
        guard let text, let data = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw failure("Expected a JSON object")
        }
        return result
    }
    static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
