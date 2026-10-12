// Created: 2026-10-12 11:06 -05:00 · Edited: 2026-10-12 11:30 -05:00
import Foundation
import HueCore

/// Persistent settings.
/// - The bridge address alone (pre-pairing state) lives in UserDefaults.
/// - Once paired, the credential record (host + app key + bridge identity) lives in the
///   Keychain as one item, so none of its parts can be edited independently (D6).
enum Settings {
    private static let d = UserDefaults.standard

    static var host: String? {
        get { d.string(forKey: "bridgeHost") }
        set { d.set(newValue, forKey: "bridgeHost") }
    }

    static var credential: BridgeCredential? {
        get { try? CredentialStore.load() }
        set {
            if let newValue { try? CredentialStore.save(newValue) } else { try? CredentialStore.delete() }
        }
    }

    /// One-time move of pre-0.2 UserDefaults secrets into the Keychain.
    static func migrateLegacyDefaults() {
        guard let key = d.string(forKey: "bridgeAppKey"), let host else { return }
        if credential == nil {
            credential = BridgeCredential(host: host, appKey: key, bridgeID: nil, certFingerprint: nil)
        }
        d.removeObject(forKey: "bridgeAppKey")
        d.removeObject(forKey: "bridgeCertSHA256")
    }
}
