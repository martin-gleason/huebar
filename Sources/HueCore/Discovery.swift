import Foundation

/// Finds bridges on the same network via Signify's cloud lookup (the bridge reports its
/// LAN address to Signify). Results are data from the internet: only private IP literals
/// are accepted as candidate addresses.
public enum Discovery {
    public struct Bridge: Codable, Equatable {
        public let id: String
        public let internalipaddress: String
        public init(id: String, internalipaddress: String) { self.id = id; self.internalipaddress = internalipaddress }
    }

    public static let endpoint = URL(string: "https://discovery.meethue.com/")!
    public static let maxResponseBytes = 64 * 1024

    public static func cloud() async throws -> [Bridge] {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 8
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if response.expectedContentLength > Int64(maxResponseBytes) { throw HueClient.HueError.responseTooLarge }
        var data = Data()
        for try await b in bytes {
            data.append(b)
            if data.count > maxResponseBytes { throw HueClient.HueError.responseTooLarge }
        }
        return validate(try JSONDecoder().decode([Bridge].self, from: data))
    }

    /// Keeps only entries whose address is a private IPv4/IPv6 literal and whose id looks
    /// like a bridge id. Hostnames and public addresses are dropped.
    public static func validate(_ bridges: [Bridge]) -> [Bridge] {
        bridges.filter { b in
            Validation.isPrivateAddress(b.internalipaddress)
                && b.id.count == 16 && b.id.lowercased().allSatisfy { $0.isHexDigit }
        }
    }
}
