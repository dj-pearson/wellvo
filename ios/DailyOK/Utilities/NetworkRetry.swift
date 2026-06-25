import Foundation

/// Retries an async operation with exponential backoff.
enum NetworkRetry {
    /// Execute an async throwing closure with retry and exponential backoff.
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default 3)
    ///   - initialDelay: Base delay in seconds before first retry (default 1.0)
    ///   - operation: The async throwing operation to execute
    /// - Returns: The result of the operation
    static func execute<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry on auth errors or deterministic client errors
                if isNonRetryable(error) {
                    throw error
                }

                // Don't sleep after the last attempt
                if attempt < maxAttempts - 1 {
                    // Honor a server-supplied Retry-After (e.g. 429/503) instead
                    // of the fixed exponential schedule when present.
                    let delay = retryAfter(for: error) ?? initialDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    /// Whether an error represents a deterministic failure that won't succeed on
    /// retry. A retried 400/403/404 just wastes ~3-7s on the "I'm OK" path.
    static func isNonRetryable(_ error: Error) -> Bool {
        // Deterministic HTTP client errors (4xx) shouldn't be retried, EXCEPT
        // 408 Request Timeout and 429 Too Many Requests, which are transient.
        if let httpError = error as? EdgeFunctionsClient.HTTPError {
            let status = httpError.status
            if status == 408 || status == 429 { return false }
            return (400..<500).contains(status)
        }

        let nsError = error as NSError

        // Don't retry auth failures, bad requests, etc.
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled,
                 NSURLErrorUserAuthenticationRequired,
                 NSURLErrorUserCancelledAuthentication:
                return true
            default:
                return false
            }
        }

        return false
    }

    /// The server-requested backoff for a retryable error (429/503 Retry-After),
    /// if any.
    private static func retryAfter(for error: Error) -> TimeInterval? {
        (error as? EdgeFunctionsClient.HTTPError)?.retryAfter
    }
}

enum NetworkError: LocalizedError {
    case maxRetriesExceeded
    case offline

    var errorDescription: String? {
        switch self {
        case .maxRetriesExceeded: return "Network request failed after multiple attempts."
        case .offline: return "You appear to be offline. Your check-in will be sent when you reconnect."
        }
    }
}
