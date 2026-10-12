import Foundation
import Security

/// What the app needs to talk to a paired bridge. Stored as one Keychain item so the
/// host, key and certificate identity cannot be edited independently of each other.
public struct BridgeCredential: Codable, Equatable {
    public var host: String
    public var appKey: String
    public var bridgeID: String?
    public var certFingerprint: String?
    public init(host: String, appKey: String, bridgeID: String?, certFingerprint: String?) {
        self.host = host; self.appKey = appKey; self.bridgeID = bridgeID; self.certFingerprint = certFingerprint
    }
}

public enum KeychainError: Error, LocalizedError {
    case status(OSStatus)
    public var errorDescription: String? {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
    var status: OSStatus { if case .status(let s) = self { return s } ; return 0 }
}

/// Minimal generic-password wrapper. Items are readable only when the Mac is unlocked and
/// are never synced or migrated to another device.
public enum KeychainStore {
    public static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attrs) { a, _ in a } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public static func load(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return out as? Data
    }

    public static func delete(service: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

public enum CredentialStore {
    public static var service = "dev.marty.HueBar"
    static let account = "bridge"

    public static func load() throws -> BridgeCredential? {
        guard let data = try KeychainStore.load(service: service, account: account) else { return nil }
        return try JSONDecoder().decode(BridgeCredential.self, from: data)
    }
    public static func save(_ c: BridgeCredential) throws {
        try KeychainStore.save(try JSONEncoder().encode(c), service: service, account: account)
    }
    public static func delete() throws {
        try KeychainStore.delete(service: service, account: account)
    }
}
