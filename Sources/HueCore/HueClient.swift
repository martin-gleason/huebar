import Foundation
import Security
import CryptoKit

/// Talks to one Hue Bridge over HTTPS using the CLIP v2 API.
/// The bridge presents a certificate signed by Signify's private root, so trust is
/// pinned on first use: the leaf certificate's SHA-256 is remembered and must match later.
public final class HueClient: NSObject, URLSessionDelegate {

    public struct Config {
        public var host: String
        public var appKey: String?
        public var certFingerprint: String?
        public init(host: String, appKey: String?, certFingerprint: String?) {
            self.host = host; self.appKey = appKey; self.certFingerprint = certFingerprint
        }
    }

    public enum HueError: Error, LocalizedError {
        case notPaired, linkButtonNotPressed, invalidHost, certificateChanged
        case http(Int), api(String)
        public var errorDescription: String? {
            switch self {
            case .notPaired: return "Not paired with the bridge"
            case .linkButtonNotPressed: return "Link button not pressed"
            case .invalidHost: return "Bridge address is not valid"
            case .certificateChanged: return "Bridge certificate changed. Set the bridge address again to re-trust it."
            case .http(let code): return "Bridge returned HTTP \(code)"
            case .api(let msg): return msg
            }
        }
    }

    public private(set) var config: Config
    /// Called (off the main thread) the first time a bridge certificate is accepted.
    public var onFingerprintLearned: ((String) -> Void)?
    private var session: URLSession!

    public init(config: Config) {
        self.config = config
        super.init()
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 10
        c.waitsForConnectivity = false
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
        if let ok = first["success"] as? [String: Any], let key = ok["username"] as? String {
            config.appKey = key
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
        let data = try await request("GET", "/clip/v2/resource/\(resource)")
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
        try await put("light/\(id)", ["on": ["on": on]])
    }

    public func setGroupedLight(_ id: String, on: Bool) async throws {
        try await put("grouped_light/\(id)", ["on": ["on": on]])
    }

    public func recallScene(_ id: String) async throws {
        try await put("scene/\(id)", ["recall": ["action": "active"]])
    }

    private func put(_ path: String, _ json: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: json)
        _ = try await request("PUT", "/clip/v2/resource/\(path)", body: body)
    }

    // MARK: Transport

    private func request(_ method: String, _ path: String, body: Data? = nil, authenticated: Bool = true) async throws -> Data {
        guard let url = URL(string: "https://\(config.host)\(path)"), url.host != nil else { throw HueError.invalidHost }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let key = config.appKey else { throw HueError.notPaired }
            req.setValue(key, forHTTPHeaderField: "hue-application-key")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError where e.code == .cancelled {
            throw HueError.certificateChanged   // our delegate cancelled the TLS challenge
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw HueError.http(code) }
        return data
    }

    // MARK: TLS trust-on-first-use

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == config.host,
              let trust = space.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return (.cancelAuthenticationChallenge, nil) }

        let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            .map { String(format: "%02x", $0) }.joined()
        if let pinned = config.certFingerprint {
            guard pinned == fingerprint else { return (.cancelAuthenticationChallenge, nil) }
        } else {
            config.certFingerprint = fingerprint
            onFingerprintLearned?(fingerprint)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
