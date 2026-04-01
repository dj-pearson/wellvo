import Foundation
import CryptoKit
import Security

/// Validates the TLS certificate chain for the Supabase server against known pins.
/// Pins to Let's Encrypt ISRG Root X1 (primary) and ISRG Root X2 (backup).
///
/// Pin rotation strategy:
/// - Pins target the root CA public key, not the leaf certificate
/// - Let's Encrypt leaf certs rotate every 90 days, but root pins are stable for years
/// - Backup pin (ISRG Root X2) provides continuity if primary root changes
/// - Update pins when Let's Encrypt announces root CA transitions
actor CertificatePinningService: NSObject {
    static let shared = CertificatePinningService()

    /// SHA-256 hashes of the Subject Public Key Info (SPKI) for trusted root CAs.
    /// ISRG Root X1: Let's Encrypt primary root
    /// ISRG Root X2: Let's Encrypt backup root (ECDSA)
    private let pinnedHashes: Set<String> = [
        "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=", // ISRG Root X1
        "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=", // ISRG Root X2
    ]

    private var lastValidationResult: Bool?
    private var lastValidationDate: Date?

    /// Validate the Supabase server certificate on app launch.
    /// Returns true if the certificate chain matches known pins.
    func validateServerCertificate() async -> Bool {
        let urlString = Configuration.supabaseURL
        guard let url = URL(string: urlString), url.scheme == "https" else {
            return true // Skip validation for non-HTTPS (debug/localhost)
        }

        // Cache result for 1 hour to avoid excessive checks
        if let lastDate = lastValidationDate,
           let lastResult = lastValidationResult,
           Date().timeIntervalSince(lastDate) < 3600 {
            return lastResult
        }

        let result = await performPinValidation(url: url)
        lastValidationResult = result
        lastValidationDate = Date()
        return result
    }

    private func performPinValidation(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let delegate = PinValidationDelegate(pinnedHashes: pinnedHashes) { result in
                continuation.resume(returning: result)
            }

            let session = URLSession(
                configuration: .ephemeral,
                delegate: delegate,
                delegateQueue: nil
            )

            // Simple HEAD request to trigger TLS handshake
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10

            let task = session.dataTask(with: request) { _, _, error in
                if error != nil, delegate.pinResult == nil {
                    delegate.complete(false)
                }
            }
            task.resume()
        }
    }
}

/// URLSession delegate that validates server certificate pins during TLS handshake.
private class PinValidationDelegate: NSObject, URLSessionDelegate {
    let pinnedHashes: Set<String>
    private var completion: ((Bool) -> Void)?
    private(set) var pinResult: Bool?

    init(pinnedHashes: Set<String>, completion: @escaping (Bool) -> Void) {
        self.pinnedHashes = pinnedHashes
        self.completion = completion
    }

    func complete(_ result: Bool) {
        guard pinResult == nil else { return }
        pinResult = result
        completion?(result)
        completion = nil
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            complete(false)
            return
        }

        // Evaluate the trust chain
        let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            complete(false)
            return
        }

        // Check if any certificate in the chain matches our pins
        let chainLength = SecTrustGetCertificateCount(serverTrust)
        var matched = false

        for i in 0..<chainLength {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            let hash = sha256OfPublicKey(certificate: certificate)
            if let hash, pinnedHashes.contains(hash) {
                matched = true
                break
            }
        }

        if matched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            complete(true)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            complete(false)
        }
    }

    /// Extract the Subject Public Key Info and compute its SHA-256 hash (base64-encoded).
    private func sha256OfPublicKey(certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        let hash = SHA256.hash(data: publicKeyData)
        return Data(hash).base64EncodedString()
    }
}
