import Foundation

/// Finds bridges on the same network via Signify's cloud lookup (the bridge reports its
/// LAN address to Signify). To grow: add an mDNS browser for `_hue._tcp` for offline use.
public enum Discovery {
    public struct Bridge: Codable {
        public let id: String
        public let internalipaddress: String
    }

    public static func cloud() async throws -> [Bridge] {
        var req = URLRequest(url: URL(string: "https://discovery.meethue.com/")!)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([Bridge].self, from: data)
    }
}
