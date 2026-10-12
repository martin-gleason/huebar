// Created: 2026-10-12 11:06 -05:00 · Edited: 2026-10-12 11:30 -05:00
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
        let client = HueClient(config: .init(host: try host, appKey: nil))
        var learned: HueClient.Config?
        client.onTrustEstablished = { learned = $0 }
        do {
            try await client.pair(deviceType: "huebar#test")
            XCTFail("Pairing succeeded unexpectedly; the link button must have been pressed")
        } catch HueClient.HueError.linkButtonNotPressed {
            // expected
        }
        XCTAssertNotNil(learned, "identity should be learned on first contact")
        XCTAssertEqual(learned?.bridgeID?.count, 16, "bridge id comes from the certificate CN")
        if let expected = ProcessInfo.processInfo.environment["HUE_BRIDGE_ID"] {
            XCTAssertEqual(learned?.bridgeID, expected.lowercased())
        }
    }

    /// The bridge is genuine but is not the one we paired with: refuse, never send the key.
    func testWrongBridgeIDIsRejected() async throws {
        let client = HueClient(config: .init(host: try host, appKey: "k", bridgeID: "0000000000000000", certFingerprint: nil))
        do { _ = try await client.fetch("light") as [Light]; XCTFail("should refuse") }
        catch HueClient.HueError.certificateChanged {}
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
        let snap = try await HueClient(config: .init(host: try host, appKey: key)).snapshot()
        XCTAssertFalse(snap.rooms.isEmpty && snap.unassigned.isEmpty)
    }
}
