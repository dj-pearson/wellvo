import Foundation
import CryptoKit
import Security

/// Shared certificate-pinning primitives used by both the out-of-band launch
/// probe (`CertificatePinningService`) and the in-line enforcement that runs on
/// every real request (`PinnedURLSession`). Keeping the hashing here means the
/// probe and the enforcement can never disagree about what a "match" is.
///
/// Pins target the **SubjectPublicKeyInfo (SPKI)** SHA-256 of the trusted root
/// CAs, base64-encoded — the same value `openssl ... | openssl dgst -sha256`
/// produces and that the wider ecosystem publishes. This is intentionally NOT
/// the raw `SecKeyCopyExternalRepresentation` bytes (which omit the ASN.1
/// algorithm header and would never match a published SPKI pin).
enum CertificatePinning {
    /// Result of evaluating a server trust against the pin set.
    enum Evaluation {
        /// Chain is system-trusted AND a pinned key was found. Proceed.
        case pinned
        /// Chain is system-trusted but NO pinned key matched. Treat as an attack
        /// (rogue but device-trusted CA, e.g. MDM/malicious profile) — fail closed.
        case mismatch
        /// Trust could not be evaluated at all (e.g. captive portal, broken
        /// chain, offline). Transient — not an attack; surface as a normal
        /// connectivity failure and allow a retry.
        case unevaluable
    }

    /// Default bundled pins: Let's Encrypt ISRG roots.
    /// ISRG Root X1 (RSA 4096) — primary; ISRG Root X2 (ECDSA P-384) — backup.
    private static let defaultPins: Set<String> = [
        "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=", // ISRG Root X1
        "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=", // ISRG Root X2
    ]

    /// Override key (App Group `UserDefaults`, shared with extensions). Lets a
    /// remote-config / MDM push a rotated pin set without an app-store update.
    /// Value: an array of base64 SPKI SHA-256 strings.
    static let overrideDefaultsKey = "pinned_spki_hashes"

    /// The active pin set: an override if present and non-empty, else the
    /// bundled defaults. Read fresh each call so a pushed rotation takes effect
    /// without relaunch.
    static var pinnedHashes: Set<String> {
        if let raw = SharedAppGroup.defaults?.array(forKey: overrideDefaultsKey) as? [String] {
            let cleaned = Set(raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            if !cleaned.isEmpty { return cleaned }
        }
        return defaultPins
    }

    /// Evaluate a server trust object against the active pin set.
    static func evaluate(_ serverTrust: SecTrust, host: String) -> Evaluation {
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            // System couldn't establish trust at all — captive portal, broken
            // chain, or offline. Not evidence of an attack.
            return .unevaluable
        }

        let pins = pinnedHashes
        let count = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<count {
            guard let cert = certificate(serverTrust, at: i),
                  let hash = spkiSHA256(for: cert) else { continue }
            if pins.contains(hash) { return .pinned }
        }
        return .mismatch
    }

    private static func certificate(_ trust: SecTrust, at index: Int) -> SecCertificate? {
        if #available(iOS 15.0, watchOS 8.0, *) {
            return (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?[safe: index]
        } else {
            return SecTrustGetCertificateAtIndex(trust, index)
        }
    }

    /// Compute the base64-encoded SHA-256 of a certificate's SPKI by prepending
    /// the correct ASN.1 algorithm header to the raw public-key bytes.
    static func spkiSHA256(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let header = asn1Header(for: publicKey),
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        var spki = Data(header)
        spki.append(keyData)
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }

    /// ASN.1 SubjectPublicKeyInfo headers per key type + size (TrustKit-derived).
    private static func asn1Header(for key: SecKey) -> [UInt8]? {
        guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attrs[kSecAttrKeyType as String] as? String,
              let bits = attrs[kSecAttrKeySizeInBits as String] as? Int else {
            return nil
        }

        switch (type, bits) {
        case (kSecAttrKeyTypeRSA as String, 2048):
            return [0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00]
        case (kSecAttrKeyTypeRSA as String, 4096):
            return [0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00]
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 256):
            return [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
                    0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                    0x42, 0x00]
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 384):
            return [0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
                    0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00]
        default:
            return nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A `URLSession` whose delegate enforces certificate pinning on the TLS
/// handshake of every request — replacing `URLSession.shared` for the sessions
/// that carry tokens and PII. A genuine pin mismatch fails the request closed; a
/// transient "couldn't evaluate" is allowed to surface as an ordinary network
/// error so a captive portal isn't mistaken for an attack.
final class PinnedURLSession {
    static let shared = PinnedURLSession()

    private let session: URLSession

    private init() {
        let delegate = PinningDelegate()
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    private final class PinningDelegate: NSObject, URLSessionDelegate {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            switch CertificatePinning.evaluate(serverTrust, host: challenge.protectionSpace.host) {
            case .pinned:
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            case .mismatch, .unevaluable:
                // Fail closed. The error surfaces to the caller as a transport
                // failure; the caller distinguishes "couldn't verify" copy.
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
