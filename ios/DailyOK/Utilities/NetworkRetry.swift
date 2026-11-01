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

                // A cancelled caller (e.g. `withDeadline` giving up) wants out
                // now, not another attempt.
                if error is CancellationError || Task.isCancelled {
                    throw error
                }

                // Don't retry on auth errors or deterministic client errors
                if isNonRetryable(error) {
                    throw error
                }

                // Don't sleep after the last attempt
                if attempt < maxAttempts - 1 {
                    // Honor a server-supplied Retry-After (e.g. 429/503) instead
                    // of the fixed exponential schedule when present.
                    let delay = retryAfter(for: error) ?? initialDelay * pow(2.0, Double(attempt))
                    // `try`, not `try?`: swallowing the CancellationError here
                    // used to turn a cancelled backoff into an immediate next
                    // attempt, so cancellation never actually stopped the loop.
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    /// Overall wall-clock budget for a check-in sent from a background
    /// notification action ("I'm OK" on the Lock Screen). iOS gives such an
    /// action roughly 30s before suspending the app; past this budget the
    /// caller stops waiting on the network and queues the check-in offline
    /// instead, leaving headroom to persist it and call the completion handler.
    static let backgroundActionBudget: TimeInterval = 20

    /// Run `operation`, but stop waiting at `deadline` and throw
    /// `NetworkError.deadlineExceeded` (which `isConnectivityError` treats as
    /// offline, so check-in callers queue). The operation is cancelled when the
    /// deadline wins; `NetworkRetry.execute` and `PinnedURLSession` both honour
    /// that cancellation promptly.
    ///
    /// The deadline is HARD: this returns at `deadline` even if `operation`
    /// ignores cancellation. A task group would not — it awaits every child
    /// before returning — and some work here doesn't stop when cancelled (the
    /// Supabase SDK awaits its session refresh in an unstructured task, on its
    /// own 60s-timeout URLSession). So the operation runs in its own task and is
    /// raced, not joined; a cancellation-deaf operation finishes in the
    /// background and its result is discarded.
    ///
    /// - A `nil` deadline runs `operation` unbounded (foreground callers).
    /// - A deadline already in the past throws without running `operation`.
    /// - Cancelling the caller throws `CancellationError` at once.
    ///
    /// A request that was already on the wire when the deadline fired may
    /// still land server-side; the queued copy is then deduplicated by the
    /// per-slot, per-day check on both the queue and `process-checkin-response`.
    static func withDeadline<T: Sendable>(
        _ deadline: Date?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let deadline else { return try await operation() }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw NetworkError.deadlineExceeded }

        let race = DeadlineRace<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let work = Task {
                    do {
                        race.finish(.success(try await operation()))
                    } catch {
                        race.finish(.failure(error))
                    }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } catch {
                        return // cancelled: the operation (or the caller) already decided
                    }
                    race.finish(.failure(NetworkError.deadlineExceeded))
                }
                race.begin(continuation: continuation, tasks: [work, timer])
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }

    /// First-outcome-wins state for `withDeadline`. Resumes the continuation
    /// exactly once, whichever of operation / timer / caller-cancel finishes
    /// first — including before `begin` has stored the continuation — and then
    /// cancels both racing tasks.
    private final class DeadlineRace<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var outcome: Result<T, Error>?
        private var tasks: [Task<Void, Never>] = []

        func begin(continuation: CheckedContinuation<T, Error>, tasks: [Task<Void, Never>]) {
            lock.lock()
            if let outcome {
                lock.unlock()
                tasks.forEach { $0.cancel() }
                continuation.resume(with: outcome)
                return
            }
            self.continuation = continuation
            self.tasks = tasks
            lock.unlock()
        }

        func finish(_ result: Result<T, Error>) {
            lock.lock()
            guard outcome == nil else {
                lock.unlock()
                return
            }
            outcome = result
            let continuation = self.continuation
            self.continuation = nil
            let tasks = self.tasks
            self.tasks = []
            lock.unlock()
            tasks.forEach { $0.cancel() }
            continuation?.resume(with: result)
        }
    }

    /// Whether an error represents a deterministic failure that won't succeed on
    /// retry. A retried 400/403/404 just wastes ~3-7s on the "I'm OK" path.
    static func isNonRetryable(_ error: Error) -> Bool {
        // A captive portal (TLS trust that can't be evaluated) won't clear in
        // the seconds a retry loop waits — the user has to sign in to the Wi-Fi.
        // Fail fast so the check-in is queued while there is still background
        // time to do it. Durable sync paths still retry it later
        // (`SyncDisposition.retryLater`).
        if case PinningError.trustUnevaluable? = error as? PinningError {
            return true
        }

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

/// What a durable sync path (the offline check-in queue, the StoreKit
/// entitlement push) should do with a row/transaction whose upload failed.
///
/// This is deliberately stricter than `NetworkRetry.isNonRetryable`, which only
/// answers "is retrying *right now, in this loop* pointless?". Dropping is
/// irreversible — a dropped check-in is a false escalation, a finished
/// unsynced transaction is a paid subscription the backend never hears about —
/// so it is reserved for failures that are provably about the payload itself.
///
/// - `dropPermanently`: the server validated the request and rejected it
///   (400, 403, 404, 409, 410, 422). It will fail identically forever.
/// - `retryLater`: everything else. Notably 401 (the edge server returns it for
///   transient auth-service failures and expired sessions that refresh), 426
///   (force update — the row must survive until the user updates), 408, 429,
///   every 5xx, connectivity / cancellation, an unevaluable TLS trust
///   (`PinningError.trustUnevaluable` — captive portal), and any unrecognized
///   error.
///
/// Pure and not actor-isolated so both `@MainActor` services and unit tests
/// can call it directly.
enum SyncDisposition: Equatable, Sendable {
    case retryLater
    case dropPermanently

    /// HTTP statuses that mean "this exact request will never be accepted".
    static let permanentRejectionStatuses: Set<Int> = [400, 403, 404, 409, 410, 422]

    init(for error: Error) {
        if let httpError = error as? EdgeFunctionsClient.HTTPError,
           Self.permanentRejectionStatuses.contains(httpError.status) {
            self = .dropPermanently
        } else {
            self = .retryLater
        }
    }
}

enum NetworkError: LocalizedError {
    case maxRetriesExceeded
    case offline
    /// `NetworkRetry.withDeadline` stopped waiting. Treated as connectivity.
    case deadlineExceeded

    var errorDescription: String? {
        switch self {
        case .maxRetriesExceeded: return "Network request failed after multiple attempts."
        case .offline: return "You appear to be offline. Your check-in will be sent when you reconnect."
        case .deadlineExceeded: return "The network took too long to respond."
        }
    }
}
