import XCTest
@testable import HueCore

/// Live tests against a real bridge. Skipped unless HUE_BRIDGE_HOST is set:
///   HUE_BRIDGE_HOST=192.168.0.189 swift test
///   HUE_BRIDGE_HOST=... HUE_APP_KEY=... swift test     (also reads the home)
final class BridgeIntegrationTests: XCTestCase {
    private var host: String { get throws {
        guard let h = ProcessInfo.processInfo.environment["HUE_BRIDGE_HOST"] else { throw XCTSkip("HUE_BRIDGE_HOST not set") }
        return h
    } }

    /// FR6: pairing without the link button pressed yields the specific error, which proves
    /// TLS pinning and the pairing endpoint work end to end.
    func testPairingWithoutLinkButtonReportsIt() async throws {
        let client = HueClient(config: .init(host: try host, appKey: nil, certFingerprint: nil))
        var learned: String?
        client.onFingerprintLearned = { learned = $0 }
        do {
            try await client.pair(deviceType: "huebar#test")
            XCTFail("Pairing succeeded unexpectedly; the link button must have been pressed")
        } catch HueClient.HueError.linkButtonNotPressed {
            // expected
        }
        XCTAssertNotNil(learned, "fingerprint should be learned on first contact")
    }

    func testWrongFingerprintIsRejected() async throws {
        let client = HueClient(config: .init(host: try host, appKey: nil, certFingerprint: String(repeating: "0", count: 64)))
        do {
            try await client.pair(deviceType: "huebar#test")
            XCTFail("should not connect with a mismatched pin")
        } catch HueClient.HueError.certificateChanged {
            // expected
        }
    }

    func testSnapshotWithKey() async throws {
        guard let key = ProcessInfo.processInfo.environment["HUE_APP_KEY"] else { throw XCTSkip("HUE_APP_KEY not set") }
        let snap = try await HueClient(config: .init(host: try host, appKey: key, certFingerprint: nil)).snapshot()
        XCTAssertFalse(snap.rooms.isEmpty && snap.unassigned.isEmpty)
    }
}
