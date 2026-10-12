import Foundation

/// Input validation for everything that arrives from outside the process: the bridge
/// address (typed or from discovery), resource ids (from bridge JSON) and display names.
public enum Validation {

    /// Returns a host suitable for `https://<host>/…`, or throws. Accepts an IPv4 literal,
    /// a bracketed IPv6 literal, or an RFC 1123 hostname. Rejects anything that could
    /// change the URL's meaning: paths, query, fragment, userinfo, ports, whitespace.
    public static func host(_ raw: String) throws -> String {
        let h = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, h.count <= 253, h.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.controlCharacters.contains($0) }) else {
            throw HueClient.HueError.invalidHost
        }
        if h.hasPrefix("[") && h.hasSuffix("]") {
            guard isIPv6(String(h.dropFirst().dropLast())) else { throw HueClient.HueError.invalidHost }
            return h
        }
        if isIPv4(h) { return h }
        for label in h.split(separator: ".", omittingEmptySubsequences: false) {
            guard (1...63).contains(label.count),
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !label.hasPrefix("-"), !label.hasSuffix("-")
            else { throw HueClient.HueError.invalidHost }
        }
        return h
    }

    /// Hue v2 resource ids are UUIDs; resource type names are short ASCII words.
    /// Anything else never reaches the URL.
    public static func resourceID(_ id: String) throws -> String {
        guard (1...64).contains(id.count),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { throw HueClient.HueError.invalidResourceID }
        return id
    }

    /// Menu-safe name: no control characters or line breaks, bounded length, never empty.
    public static func displayName(_ raw: String, maxLength: Int = 60) -> String {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
        var s = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = "Unnamed" }
        if s.count > maxLength { s = String(s.prefix(maxLength - 1)) + "…" }
        return s
    }

    public static func isIPv4(_ s: String) -> Bool {
        var a = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &a) == 1 }
    }

    public static func isIPv6(_ s: String) -> Bool {
        var a = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &a) == 1 }
    }

    /// RFC 1918, link-local, IPv6 ULA and link-local. A bridge is always on the LAN.
    public static func isPrivateAddress(_ s: String) -> Bool {
        if isIPv4(s) {
            let p = s.split(separator: ".").compactMap { UInt8($0) }
            guard p.count == 4 else { return false }
            return p[0] == 10
                || (p[0] == 172 && (16...31).contains(p[1]))
                || (p[0] == 192 && p[1] == 168)
                || (p[0] == 169 && p[1] == 254)
        }
        if isIPv6(s) {
            var a = in6_addr()
            _ = s.withCString { inet_pton(AF_INET6, $0, &a) }
            let b0 = a.__u6_addr.__u6_addr8.0, b1 = a.__u6_addr.__u6_addr8.1
            return (b0 & 0xfe) == 0xfc || (b0 == 0xfe && (b1 & 0xc0) == 0x80)
        }
        return false
    }
}
