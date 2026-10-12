import Foundation
import Security
import CryptoKit

/// Validates a bridge's TLS certificate against Signify's published `root-bridge` CA and
/// extracts the bridge id from the certificate's common name.
///
/// Every Hue Bridge v2 (firmware 1.24+) presents a leaf certificate with CN = bridge id,
/// issued by this root. The certificate carries no subjectAltName, so hostname/IP checks
/// are not possible; identity is the bridge id instead.
public enum BridgeTrust {

    public struct Identity: Equatable {
        public let bridgeID: String       // 16 lowercase hex chars
        public let fingerprint: String    // SHA-256 of the leaf, lowercase hex
    }

    /// Signify "root-bridge" CA, SHA-256 f0bd8e6509e82f774d63bc009d5388c969fe3dcf7d6d541d6351b72b898d8acf
    static let rootDERBase64 = "MIICMjCCAdigAwIBAgIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIwOTELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRQwEgYDVQQDDAtyb290LWJyaWRnZTAiGA8yMDE3MDEwMTAwMDAwMFoYDzIwMzgwMTE5MDMxNDA3WjA5MQswCQYDVQQGEwJOTDEUMBIGA1UECgwLUGhpbGlwcyBIdWUxFDASBgNVBAMMC3Jvb3QtYnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjNw2tx2AplOf9x86aTdvEcL1FU65QDxziKvBpW9XXSIcibAeQiKxegpq8Exbr9v6LBnYbna2VcaK0G22jOKkTqOBuTCBtjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUZ2ONTFrDT6o8ItRnKfqWKnHFGmQwdAYDVR0jBG0wa4AUZ2ONTFrDT6o8ItRnKfqWKnHFGmShPaQ7MDkxCzAJBgNVBAYTAk5MMRQwEgYDVQQKDAtQaGlsaXBzIEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2WCFDuxUi22sYpLlwJY81Wrqy11phcOMAoGCCqGSM49BAMCA0gAMEUCIEBYYEOsa07TH7E5MJnGw557lVkORgit2Rm1h3B2sFgDAiEA1Fj/C3AN5psFMjo0//mrQebo0eKd3aWRx+pQY08mk48="

    public static let rootCertificate: SecCertificate = {
        guard let der = Data(base64Encoded: rootDERBase64),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            preconditionFailure("embedded Hue root certificate is malformed")
        }
        return cert
    }()

    /// Evaluates `trust` strictly against the Hue root (system roots are ignored) and
    /// returns the bridge identity. Throws `HueError.untrustedBridge` otherwise.
    public static func evaluate(_ trust: SecTrust) throws -> Identity {
        SecTrustSetAnchorCertificates(trust, [rootCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil))   // no name check: the leaf has no SAN
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            throw HueClient.HueError.untrustedBridge((error as Error?)?.localizedDescription ?? "certificate not issued by the Hue root")
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count >= 2, let leaf = chain.first else {
            throw HueClient.HueError.untrustedBridge("certificate is not issued by the Hue root")
        }
        let cn = (SecCertificateCopySubjectSummary(leaf) as String?)?.lowercased() ?? ""
        guard cn.count == 16, cn.allSatisfy({ $0.isHexDigit }) else {
            throw HueClient.HueError.untrustedBridge("certificate name is not a bridge id")
        }
        return Identity(bridgeID: cn, fingerprint: sha256Hex(SecCertificateCopyData(leaf) as Data))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
