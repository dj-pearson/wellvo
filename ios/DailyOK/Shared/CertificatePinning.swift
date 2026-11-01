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

        // Bind the Security constants to `String` locals up front. Inlining them
        // as `case (kSecAttrKeyTypeRSA as String, …)` makes the compiler read
        // `… as String` as a cast *pattern* over a `CFString` expression, which
        // no longer type-checks against the `String` value being switched on
        // ("expression pattern of type 'CFString' cannot match values of type
        // 'String'"). As plain `String` locals they are ordinary `==` patterns.
        let rsaKeyType = kSecAttrKeyTypeRSA as String
        let ecKeyType = kSecAttrKeyTypeECSECPrimeRandom as String

        switch (type, bits) {
        case (rsaKeyType, 2048):
            return [0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00]
        case (rsaKeyType, 4096):
            return [0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00]
        case (ecKeyType, 256):
            return [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
                    0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                    0x42, 0x00]
        case (ecKeyType, 384):
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

/// Thrown by `PinnedURLSession` when the server trust could not be evaluated at
/// all (`CertificatePinning.Evaluation.unevaluable`) — the typical captive
/// portal (hotel / airport Wi-Fi intercepting TLS before sign-in), a broken
/// chain, or a network that drops mid-handshake.
///
/// Before this existed the delegate cancelled the challenge and the caller saw
/// a bare `NSURLErrorCancelled`, which nothing classified as "offline" — so an
/// "I'm OK" on hotel Wi-Fi was surfaced as a hard error instead of being queued
/// for later sync. Callers treat this as a connectivity failure
/// (`OfflineCheckInService.isConnectivityError`) and the durable sync paths as
/// `SyncDisposition.retryLater`.
///
/// A genuine pin MISMATCH (system-trusted chain, no pinned key) is NOT this
/// error: it still fails closed as a cancelled request, unchanged.
enum PinningError: LocalizedError, Equatable {
    case trustUnevaluable

    var errorDescription: String? {
        switch self {
        case .trustUnevaluable:
            return "Couldn't establish a secure connection. If you're on public Wi-Fi, you may need to sign in to it first."
        }
    }
}

/// A `URLSession` whose delegate enforces certificate pinning on the TLS
/// handshake of every request — replacing `URLSession.shared` for the sessions
/// that carry tokens and PII. A genuine pin mismatch fails the request closed; a
/// transient "couldn't evaluate" surfaces as `PinningError.trustUnevaluable` so
/// a captive portal isn't mistaken for an attack (and is queued as offline).
final class PinnedURLSession {
    static let shared = PinnedURLSession()

    private let session: URLSession
    private let delegate: PinningDelegate

    private init() {
        let delegate = PinningDelegate()
        self.delegate = delegate
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    /// Same contract as `URLSession.data(for:)` (including throwing
    /// `NSURLErrorCancelled` when the calling task is cancelled), except that a
    /// trust that couldn't be evaluated throws `PinningError.trustUnevaluable`.
    ///
    /// Built on a completion-handler data task rather than the async
    /// `data(for:)` so the failure can be matched to the task whose challenge
    /// was unevaluable (by `taskIdentifier`) — concurrent requests can't
    /// misattribute each other's outcome.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let handle = TaskHandle()
        let delegate = self.delegate
        let session = self.session
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    let unevaluable = handle.identifier.map { delegate.takeUnevaluable(taskIdentifier: $0) } ?? false
                    if let error {
                        continuation.resume(throwing: unevaluable ? PinningError.trustUnevaluable : error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                handle.start(task)
            }
        } onCancel: {
            handle.cancel()
        }
    }

    /// Holds the data task so the cancellation handler (which may run before
    /// the task exists, or concurrently with its creation) can cancel it.
    private final class TaskHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false

        var identifier: Int? {
            lock.lock(); defer { lock.unlock() }
            return task?.taskIdentifier
        }

        /// Record and resume the task; cancel it at once if the calling Swift
        /// task was already cancelled.
        func start(_ task: URLSessionTask) {
            lock.lock()
            self.task = task
            let alreadyCancelled = cancelled
            lock.unlock()
            task.resume()
            if alreadyCancelled { task.cancel() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    /// Implements only the TASK-level challenge method. Per the URLSession
    /// contract, a server-trust challenge goes to the session-level
    /// `urlSession(_:didReceive:completionHandler:)` only if the delegate
    /// implements it; otherwise it is delivered here, with the task — which is
    /// what lets an unevaluable trust be attributed to the right request.
    private final class PinningDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var unevaluableTasks: Set<Int> = []

        /// Whether `taskIdentifier`'s challenge was unevaluable; clears the mark.
        func takeUnevaluable(taskIdentifier: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return unevaluableTasks.remove(taskIdentifier) != nil
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
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
            case .mismatch:
                // Fail closed: possible interception by a device-trusted rogue
                // CA. Surfaces as a cancelled request, never queued as offline.
                completionHandler(.cancelAuthenticationChallenge, nil)
            case .unevaluable:
                // Still fail closed — nothing is sent over a connection we
                // couldn't verify — but mark the task so `data(for:)` throws
                // `PinningError.trustUnevaluable` instead of a bare cancel.
                lock.lock()
                unevaluableTasks.insert(task.taskIdentifier)
                lock.unlock()
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
