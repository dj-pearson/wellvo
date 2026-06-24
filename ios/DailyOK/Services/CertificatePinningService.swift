import Foundation
import Security

/// Out-of-band launch/resume probe that checks the Supabase host's TLS chain
/// against the pinned roots (see `CertificatePinning`). This is an *early
/// warning* — the authoritative enforcement happens inline on every real
/// request via `PinnedURLSession`. The probe lets the app surface a clear
/// "secure connection couldn't be verified" state proactively rather than only
/// when the next API call fails.
///
/// Pins target the root CA SPKI, which is stable for years; leaf certs rotating
/// every ~90 days don't affect them. The active pin set is configurable at
/// runtime (`CertificatePinning.overrideDefaultsKey`) so a rotation can ship
/// without an app update.
actor CertificatePinningService {
    static let shared = CertificatePinningService()

    private var lastResult: CertificatePinning.Evaluation?
    private var lastValidationDate: Date?

    /// Probe the Supabase server certificate. Returns the evaluation so callers
    /// can distinguish a genuine pin mismatch (attack — block) from a transient
    /// "couldn't evaluate" (e.g. captive portal — retry).
    func validate() async -> CertificatePinning.Evaluation {
        let urlString = Configuration.supabaseURL
        guard let url = URL(string: urlString), url.scheme == "https" else {
            return .pinned // Non-HTTPS (debug/localhost) — nothing to pin.
        }

        // Cache for 1 hour to avoid excessive handshakes.
        if let lastDate = lastValidationDate, let lastResult,
           Date().timeIntervalSince(lastDate) < 3600 {
            return lastResult
        }

        let result = await performProbe(url: url)
        lastResult = result
        lastValidationDate = Date()
        return result
    }

    /// Back-compat boolean: true only when a pinned key was found.
    func validateServerCertificate() async -> Bool {
        await validate() == .pinned
    }

    private func performProbe(url: URL) async -> CertificatePinning.Evaluation {
        await withCheckedContinuation { continuation in
            let delegate = ProbeDelegate { continuation.resume(returning: $0) }
            let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10

            let task = session.dataTask(with: request) { _, _, error in
                // If the handshake failed before the auth challenge resolved our
                // result, treat it as transient/unevaluable.
                if error != nil { delegate.complete(.unevaluable) }
            }
            task.resume()
        }
    }
}

/// URLSession delegate that evaluates the pin set during the TLS handshake.
private final class ProbeDelegate: NSObject, URLSessionDelegate {
    private var completion: ((CertificatePinning.Evaluation) -> Void)?
    private var finished = false

    init(completion: @escaping (CertificatePinning.Evaluation) -> Void) {
        self.completion = completion
    }

    func complete(_ result: CertificatePinning.Evaluation) {
        guard !finished else { return }
        finished = true
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
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let evaluation = CertificatePinning.evaluate(serverTrust, host: challenge.protectionSpace.host)
        switch evaluation {
        case .pinned:
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        case .mismatch, .unevaluable:
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        complete(evaluation)
    }
}
