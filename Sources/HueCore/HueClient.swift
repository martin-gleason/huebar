import Foundation
import Security

/// Talks to one Hue Bridge over HTTPS using the CLIP v2 API.
///
/// Trust model: the bridge certificate must chain to Signify's `root-bridge` CA
/// (`BridgeTrust`). On first contact the bridge id and leaf fingerprint are recorded;
/// afterwards both must match, so a different (even genuine) bridge at the same address
/// is refused until the user sets the address again.
public final class HueClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

    public struct Config: Equatable {
        public var host: String
        public var appKey: String?
        public var bridgeID: String?
        public var certFingerprint: String?
        public init(host: String, appKey: String?, bridgeID: String? = nil, certFingerprint: String? = nil) {
            self.host = host; self.appKey = appKey; self.bridgeID = bridgeID; self.certFingerprint = certFingerprint
        }
    }

    public enum HueError: Error, LocalizedError, Equatable {
        case notPaired, linkButtonNotPressed, invalidHost, invalidResourceID, certificateChanged, responseTooLarge
        case untrustedBridge(String)
        case http(Int)
        case api(String)
        public var errorDescription: String? {
            switch self {
            case .notPaired: return "Not paired with the bridge"
            case .linkButtonNotPressed: return "Link button not pressed"
            case .invalidHost: return "Bridge address is not valid"
            case .invalidResourceID: return "Bridge sent an invalid resource id"
            case .certificateChanged: return "Bridge identity changed. Set the bridge address again to trust the new bridge."
            case .responseTooLarge: return "Bridge response too large"
            case .untrustedBridge(let why): return "Untrusted bridge: \(bounded(why))"
            case .http(let code): return "Bridge returned HTTP \(code)"
            case .api(let msg): return bounded(msg)
            }
        }
        private func bounded(_ s: String) -> String { String(Validation.displayName(s, maxLength: 120)) }
    }

    public static let maxResponseBytes = 4 * 1024 * 1024

    private let lock = NSLock()
    private var _config: Config
    private var lastTrustFailure: HueError?
    public var config: Config { lock.withLock { _config } }

    /// Called off the main thread when the bridge identity is first recorded (or confirmed
    /// after pairing), with the updated config, so the caller can persist it.
    public var onTrustEstablished: ((Config) -> Void)?

    private var session: URLSession!

    public convenience init(config: Config) {
        self.init(config: config, protocolClasses: nil)
    }

    /// `protocolClasses` lets tests stub the transport; the app never passes it.
    init(config: Config, protocolClasses: [AnyClass]?) {
        _config = config
        super.init()
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 10
        c.waitsForConnectivity = false
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        if let protocolClasses { c.protocolClasses = protocolClasses }
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }

    // MARK: Pairing (v1 endpoint; the only part of the API that is not under /clip/v2)

    /// Requires the bridge's link button to have been pressed in the last ~30 seconds.
    @discardableResult
    public func pair(deviceType: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["devicetype": deviceType, "generateclientkey": true])
        let data = try await request("POST", "/api", body: body, authenticated: false)
        guard let replies = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = replies.first else {
            throw HueError.api("Unexpected pairing reply")
        }
        if let ok = first["success"] as? [String: Any], let key = ok["username"] as? String, !key.isEmpty {
            lock.withLock { _config.appKey = key }
            return key
        }
        if let err = first["error"] as? [String: Any] {
            if (err["type"] as? Int) == 101 { throw HueError.linkButtonNotPressed }
            throw HueError.api(err["description"] as? String ?? "Pairing failed")
        }
        throw HueError.api("Unexpected pairing reply")
    }

    // MARK: Reading

    public func fetch<T: Codable>(_ resource: String) async throws -> [T] {
        let data = try await request("GET", "/clip/v2/resource/\(try Validation.resourceID(resource))")
        return try JSONDecoder().decode(Envelope<T>.self, from: data).data
    }

    public func snapshot() async throws -> HueSnapshot {
        async let lights: [Light] = fetch("light")
        async let rooms: [Group] = fetch("room")
        async let zones: [Group] = fetch("zone")
        async let scenes: [Scene] = fetch("scene")
        async let home: [BridgeHome] = fetch("bridge_home")
        return try await HueSnapshot.build(lights: lights, rooms: rooms, zones: zones, scenes: scenes, home: home.first)
    }

    // MARK: Writing

    public func setLight(_ id: String, on: Bool) async throws {
        try await put("light/\(try Validation.resourceID(id))", ["on": ["on": on]])
    }

    public func setGroupedLight(_ id: String, on: Bool) async throws {
        try await put("grouped_light/\(try Validation.resourceID(id))", ["on": ["on": on]])
    }

    public func recallScene(_ id: String) async throws {
        try await put("scene/\(try Validation.resourceID(id))", ["recall": ["action": "active"]])
    }

    private func put(_ path: String, _ json: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: json)
        _ = try await request("PUT", "/clip/v2/resource/\(path)", body: body)
    }

    // MARK: Transport

    private func request(_ method: String, _ path: String, body: Data? = nil, authenticated: Bool = true) async throws -> Data {
        let cfg = config
        let host = try Validation.host(cfg.host)
        guard let url = URL(string: "https://\(host)\(path)"), url.host != nil else { throw HueError.invalidHost }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let key = cfg.appKey else { throw HueError.notPaired }
            req.setValue(key, forHTTPHeaderField: "hue-application-key")
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        lock.withLock { lastTrustFailure = nil }
        do {
            (bytes, response) = try await session.bytes(for: req)
        } catch let e as URLError {
            // Our delegate refused the TLS challenge: report why, never the generic URL error.
            if let why = lock.withLock({ lastTrustFailure }) { throw why }
            if e.code == .cancelled || e.code == .serverCertificateUntrusted { throw HueError.certificateChanged }
            throw e
        }
        if response.expectedContentLength > Int64(Self.maxResponseBytes) { throw HueError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxResponseBytes { throw HueError.responseTooLarge }
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw HueError.http(code) }
        return data
    }

    // MARK: TLS

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        handle(challenge)
    }

    // The streaming API (`bytes(for:)`) routes server-trust challenges here, not to the session-level method.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (disposition, credential) = handle(challenge)
        completionHandler(disposition, credential)
    }

    private func handle(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let identity: BridgeTrust.Identity
        do { identity = try BridgeTrust.evaluate(trust) } catch {
            lock.withLock { lastTrustFailure = (error as? HueError) ?? .untrustedBridge("certificate rejected") }
            return (.cancelAuthenticationChallenge, nil)
        }
        guard let cfgHost = try? Validation.host(config.host), space.host == cfgHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else {
            lock.withLock { lastTrustFailure = .invalidHost }
            return (.cancelAuthenticationChallenge, nil)
        }

        var learned: Config?
        let accepted: Bool = lock.withLock {
            if let id = _config.bridgeID, id != identity.bridgeID { return false }
            if let fp = _config.certFingerprint, fp != identity.fingerprint { return false }
            if _config.bridgeID == nil || _config.certFingerprint == nil {
                _config.bridgeID = identity.bridgeID
                _config.certFingerprint = identity.fingerprint
                learned = _config
            }
            return true
        }
        guard accepted else {
            lock.withLock { lastTrustFailure = .certificateChanged }
            return (.cancelAuthenticationChallenge, nil)
        }
        if let learned { onTrustEstablished?(learned) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
