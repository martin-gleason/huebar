import Foundation

/// Persistent settings. UserDefaults is deliberate for v0.1 (barebones); the app key is a
/// bridge credential, so moving it to the Keychain is the first thing to grow here.
enum Settings {
    private static let d = UserDefaults.standard

    static var host: String? {
        get { d.string(forKey: "bridgeHost") }
        set { d.set(newValue, forKey: "bridgeHost") }
    }
    static var appKey: String? {
        get { d.string(forKey: "bridgeAppKey") }
        set { d.set(newValue, forKey: "bridgeAppKey") }
    }
    static var certFingerprint: String? {
        get { d.string(forKey: "bridgeCertSHA256") }
        set { d.set(newValue, forKey: "bridgeCertSHA256") }
    }
}
