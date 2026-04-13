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

                // Don't retry on auth errors or client errors
                if isNonRetryable(error) {
                    throw error
                }

                // Don't sleep after the last attempt
                if attempt < maxAttempts - 1 {
                    let delay = initialDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    private static func isNonRetryable(_ error: Error) -> Bool {
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
