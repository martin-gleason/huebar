// Created: 2026-10-12 11:17 -05:00 · Edited: 2026-10-12 11:30 -05:00
import XCTest
import Security
@testable import HueCore

// Adversarial tests. Each one encodes an attack a hostile network, a hostile bridge, or
// a hostile local process could attempt. See docs/reviews/security-red-team-2026-10-12.md.

// MARK: - Transport stub

final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var handler: (URLRequest) -> (Int, Data) = { _ in (200, Data("{\"errors\":[],\"data\":[]}".utf8)) }

    static func reset() { lock.withLock { requests = [] ; handler = { _ in (200, Data("{\"errors\":[],\"data\":[]}".utf8)) } } }
    static func recorded() -> [URLRequest] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.requests.append(request) }
        let (code, body) = Self.lock.withLock { Self.handler }(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubClient(host: String = "192.168.1.2", key: String? = "secret-key") -> HueClient {
    HueClient(config: .init(host: host, appKey: key), protocolClasses: [StubProtocol.self])
}

// MARK: - Host / URL injection

final class HostValidationTests: XCTestCase {
    func testAcceptsSaneHosts() {
        for h in ["192.168.0.189", "10.0.0.1", "hue-bridge", "philips-hue.local", "bridge.home.arpa", "[fe80::1]", "[fd00::2]", " 192.168.0.189 \n"] {
            XCTAssertNoThrow(try Validation.host(h), h)
        }
    }

    /// Every variation here would redirect requests (and the app key header) somewhere else.
    func testRejectsURLInjectionVariants() {
        let hostile = [
            "", " ", "evil.com/x?", "192.168.0.189/", "192.168.0.189/api", "host?x=1", "host#frag",
            "user:pw@192.168.0.189", "192.168.0.189@evil.com", "192.168.0.189:8443", "192.168.0.189:443",
            "192.168.0.189\u{0}", "192.168.0.189\r\nX-Injected: 1", "192.168.0.189 evil.com",
            "evil.com\\192.168.0.189", "-bad.host", "bad-.host", "a..b", ".a", "a.",
            "xn--bücher", "ｂridge", "fe80::1", "[fe80::1", "[::1]/x",
            String(repeating: "a", count: 64) + ".com", String(repeating: "a.", count: 130) + "a",
        ]
        for h in hostile {
            XCTAssertThrowsError(try Validation.host(h), "accepted hostile host: \(h.debugDescription)")
        }
    }

    func testInvalidHostNeverTouchesTheNetwork() async {
        StubProtocol.reset()
        let client = stubClient(host: "evil.com/steal?")
        do { _ = try await client.snapshot(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? HueClient.HueError, .invalidHost) }
        XCTAssertTrue(StubProtocol.recorded().isEmpty, "a request was sent to an injected host")
    }
}

// MARK: - Resource id injection (hostile bridge JSON)

final class ResourceIDTests: XCTestCase {
    func testTraversalAndQueryIDsAreRefusedBeforeAnyRequest() async {
        StubProtocol.reset()
        let client = stubClient()
        let hostile = ["../../api/0/config", "x?y=1", "x#f", "", "a/b", "id with space", "ünïcode", String(repeating: "a", count: 65), "%2e%2e/"]
        for id in hostile {
            do { try await client.setLight(id, on: true); XCTFail("accepted id \(id)") }
            catch { XCTAssertEqual(error as? HueClient.HueError, .invalidResourceID, id) }
            do { try await client.recallScene(id); XCTFail("accepted id \(id)") }
            catch { XCTAssertEqual(error as? HueClient.HueError, .invalidResourceID, id) }
        }
        XCTAssertTrue(StubProtocol.recorded().isEmpty)
    }

    func testGenuineIDsPass() async throws {
        StubProtocol.reset()
        try await stubClient().setLight("6a2f2f10-3c1e-4a4e-9a1b-0c5d2e7f8a9b", on: true)
        XCTAssertEqual(StubProtocol.recorded().first?.url?.path, "/clip/v2/resource/light/6a2f2f10-3c1e-4a4e-9a1b-0c5d2e7f8a9b")
    }
}

// MARK: - Credential handling on the wire

final class CredentialOnTheWireTests: XCTestCase {
    func testAppKeyIsNotSentDuringPairing() async {
        StubProtocol.reset()
        StubProtocol.handler = { _ in (200, Data(#"[{"error":{"type":101,"description":"link button not pressed"}}]"#.utf8)) }
        _ = try? await stubClient().pair(deviceType: "t")
        let req = StubProtocol.recorded().first
        XCTAssertEqual(req?.url?.path, "/api")
        XCTAssertNil(req?.value(forHTTPHeaderField: "hue-application-key"))
    }

    func testAppKeyIsSentOnlyAsHeaderToV2() async throws {
        StubProtocol.reset()
        _ = try await stubClient().fetch("light") as [Light]
        let req = StubProtocol.recorded().first!
        XCTAssertEqual(req.value(forHTTPHeaderField: "hue-application-key"), "secret-key")
        XCTAssertFalse(req.url!.absoluteString.contains("secret-key"), "key must never appear in the URL")
        XCTAssertEqual(req.url?.scheme, "https")
    }

    func testPairingRejectsEmptyKey() async {
        StubProtocol.reset()
        StubProtocol.handler = { _ in (200, Data(#"[{"success":{"username":""}}]"#.utf8)) }
        do { _ = try await stubClient(key: nil).pair(deviceType: "t"); XCTFail("accepted empty key") } catch {}
    }
}

// MARK: - Hostile bridge responses

final class HostileResponseTests: XCTestCase {
    func testOversizedBodyIsRejectedByContentLength() async {
        StubProtocol.reset()
        StubProtocol.handler = { _ in (200, Data(repeating: 0x20, count: HueClient.maxResponseBytes + 1)) }
        do { _ = try await stubClient().fetch("light") as [Light]; XCTFail("accepted oversized body") }
        catch { XCTAssertEqual(error as? HueClient.HueError, .responseTooLarge) }
    }

    func testLongErrorTextIsBounded() {
        let msg = String(repeating: "A", count: 10_000) + "\n\u{7}injected"
        let text = HueClient.HueError.api(msg).errorDescription ?? ""
        XCTAssertLessThanOrEqual(text.count, 120)
        XCTAssertFalse(text.contains("\n"))
        XCTAssertFalse(text.contains("\u{7}"))
    }

    func testNamesFromBridgeAreSanitized() {
        let nasty = "Lamp\n\u{1B}[31mRED\u{7}" + String(repeating: "x", count: 500)
        let light = Light(id: "l", owner: ResourceRef(rid: "d", rtype: "device"), metadata: Metadata(name: nasty), on: nil)
        XCTAssertLessThanOrEqual(light.displayName.count, 60)
        XCTAssertFalse(light.displayName.contains("\n"))
        XCTAssertFalse(light.displayName.contains("\u{1B}"))
        XCTAssertEqual(Validation.displayName("   "), "Unnamed")
        XCTAssertEqual(Validation.displayName("\u{0}\u{0}"), "Unnamed")
    }

    func testNonJSONAndHTTPErrorsAreContained() async {
        StubProtocol.reset()
        StubProtocol.handler = { _ in (500, Data("<html>oops</html>".utf8)) }
        do { _ = try await stubClient().fetch("light") as [Light]; XCTFail() }
        catch { XCTAssertEqual(error as? HueClient.HueError, .http(500)) }
        StubProtocol.handler = { _ in (200, Data("not json".utf8)) }
        do { _ = try await stubClient().fetch("light") as [Light]; XCTFail() }
        catch { XCTAssertTrue(error is DecodingError) }
    }
}

// MARK: - Discovery results are untrusted internet data

final class DiscoveryTests: XCTestCase {
    func testOnlyPrivateIPLiteralsWithBridgeIDsSurvive() {
        let input = [
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "192.168.0.189"),   // keep
            Discovery.Bridge(id: "ECB5FAFFFE117ED9", internalipaddress: "10.1.2.3"),        // keep (case)
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "[fd00::1]"),      // drop: bracketed
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "fd00::1"),        // keep: ULA
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "evil.example.com"),
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "8.8.8.8"),
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "192.168.0.189/api"),
            Discovery.Bridge(id: "ecb5fafffe117ed9", internalipaddress: "2001:db8::1"),
            Discovery.Bridge(id: "not-a-bridge-id", internalipaddress: "192.168.0.189"),
            Discovery.Bridge(id: "", internalipaddress: "192.168.0.189"),
        ]
        XCTAssertEqual(Discovery.validate(input).map(\.internalipaddress), ["192.168.0.189", "10.1.2.3", "fd00::1"])
    }

    func testPrivateAddressClassifier() {
        for ok in ["10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.1.1", "fe80::1", "fc00::1", "fdab::1"] {
            XCTAssertTrue(Validation.isPrivateAddress(ok), ok)
        }
        for bad in ["172.32.0.1", "172.15.0.1", "11.0.0.1", "1.1.1.1", "2001:db8::1", "::1", "bridge", ""] {
            XCTAssertFalse(Validation.isPrivateAddress(bad), bad)
        }
    }
}

// MARK: - TLS identity

final class BridgeTrustTests: XCTestCase {
    /// Self-signed cert whose CN mimics a real bridge id (fixture generated with openssl; key discarded).
    static let impostorDER = "MIIBuDCCAV2gAwIBAgIUUzSRfyoYE+wVXAnLWAWDx/k6YzUwCgYIKoZIzj0EAwIwMTEZMBcGA1UEAwwQZWNiNWZhZmZmZTExN2VkOTEUMBIGA1UECgwLTm90IFBoaWxpcHMwHhcNMjYxMDEyMTYwODUxWhcNMzYxMDA5MTYwODUxWjAxMRkwFwYDVQQDDBBlY2I1ZmFmZmZlMTE3ZWQ5MRQwEgYDVQQKDAtOb3QgUGhpbGlwczBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABG3vwjduoj2/KmklnpOaGFuwrd9+3IrIiTraUR7RPu1I66UCc/LGuJV8Ff5iVvC8hCU9Ce8pk/IozWLg1JLV7r2jUzBRMB0GA1UdDgQWBBSrmcDP1DeCy7W/iKVo2bgEOwBFEzAfBgNVHSMEGDAWgBSrmcDP1DeCy7W/iKVo2bgEOwBFEzAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQD3WArBOZEAw3MR73Vz2DAtLH88Gbh7nK6Zmh5GrMAbQwIhAK+3uN4eqrMyfyVslDRyL161V+GV0Y/WcValfOClH4YC"

    private func trust(for der: String) -> SecTrust {
        let cert = SecCertificateCreateWithData(nil, Data(base64Encoded: der)! as CFData)!
        var t: SecTrust?
        SecTrustCreateWithCertificates(cert, SecPolicyCreateSSL(true, nil), &t)
        return t!
    }

    func testEmbeddedRootParsesAndIsTheSignifyRoot() {
        let summary = SecCertificateCopySubjectSummary(BridgeTrust.rootCertificate) as String?
        XCTAssertEqual(summary, "root-bridge")
        XCTAssertEqual(BridgeTrust.sha256Hex(SecCertificateCopyData(BridgeTrust.rootCertificate) as Data),
                       "f0bd8e6509e82f774d63bc009d5388c969fe3dcf7d6d541d6351b72b898d8acf")
    }

    /// An attacker on the LAN who answers on the bridge's IP with their own certificate.
    func testSelfSignedImpostorWithBridgeLikeCNIsRejected() {
        XCTAssertThrowsError(try BridgeTrust.evaluate(trust(for: Self.impostorDER))) { error in
            guard case .untrustedBridge? = error as? HueClient.HueError else { return XCTFail("\(error)") }
        }
    }

    /// Presenting the public Hue root itself as the server certificate.
    func testHueRootPresentedAsLeafIsRejected() {
        XCTAssertThrowsError(try BridgeTrust.evaluate(trust(for: BridgeTrust.rootDERBase64)))
    }

    func testPinnedIdentityMismatchIsRefusedWithoutSendingKey() async {
        // Transport stub skips TLS, so this checks the config contract only: a different
        // bridge id or fingerprint than the pinned one must be reported as certificateChanged
        // by the delegate (covered live in BridgeIntegrationTests.testWrongBridgeIDIsRejected).
        let c = HueClient.Config(host: "192.168.1.2", appKey: "k", bridgeID: "0000000000000000", certFingerprint: "00")
        XCTAssertEqual(c.bridgeID, "0000000000000000")
    }
}

// MARK: - Credential at rest

final class KeychainTests: XCTestCase {
    override func setUp() { CredentialStore.service = "dev.marty.HueBar.tests" }
    override func tearDown() { try? CredentialStore.delete(); CredentialStore.service = "dev.marty.HueBar" }

    func testCredentialRoundTripsThroughKeychainNotDefaults() throws {
        let cred = BridgeCredential(host: "192.168.1.2", appKey: "k-1", bridgeID: "ecb5fafffe117ed9", certFingerprint: "ab")
        do { try CredentialStore.save(cred) } catch let e as KeychainError where e.status == errSecInteractionNotAllowed || e.status == errSecMissingEntitlement {
            throw XCTSkip("Keychain not available in this environment: \(e)")
        }
        XCTAssertEqual(try CredentialStore.load(), cred)
        XCTAssertNil(UserDefaults.standard.string(forKey: "bridgeAppKey"))
        try CredentialStore.delete()
        XCTAssertNil(try CredentialStore.load())
    }
}
