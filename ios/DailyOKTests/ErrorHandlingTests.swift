import XCTest
@testable import DailyOK

/// Tests for DailyOKError centralized error handling
final class ErrorHandlingTests: XCTestCase {

    // MARK: - DailyOKError

    func testNetworkErrorDescription() {
        let underlyingError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let error = DailyOKError.network(underlyingError)
        XCTAssertTrue(error.localizedDescription.contains("Network error"))
    }

    func testAuthErrorDescription() {
        let error = DailyOKError.auth("Session expired")
        XCTAssertEqual(error.localizedDescription, "Session expired")
    }

    func testNotFoundErrorDescription() {
        let error = DailyOKError.notFound("Family")
        XCTAssertEqual(error.localizedDescription, "Family not found.")
    }

    func testServerErrorDescription() {
        let error = DailyOKError.serverError("Internal server error")
        XCTAssertTrue(error.localizedDescription.contains("Server error"))
    }

    func testOfflineErrorDescription() {
        let error = DailyOKError.offline
        XCTAssertTrue(error.localizedDescription.contains("offline"))
    }

    func testUnknownErrorDescription() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        let error = DailyOKError.unknown(underlying)
        XCTAssertEqual(error.localizedDescription, "Something went wrong")
    }

    // MARK: - AuthError

    func testAuthErrorInvalidEmail() {
        let error = AuthError.invalidEmail
        XCTAssertEqual(error.localizedDescription, "Please enter a valid email address.")
    }

    func testAuthErrorPasswordTooShort() {
        let error = AuthError.passwordTooShort
        XCTAssertEqual(error.localizedDescription, "Password must be at least 8 characters.")
    }

    func testAuthErrorPasswordTooWeak() {
        let error = AuthError.passwordTooWeak
        XCTAssertTrue(error.localizedDescription.contains("uppercase"))
    }

    // MARK: - CheckInError

    func testCheckInNotAuthenticated() {
        let error = CheckInError.notAuthenticated
        XCTAssertTrue(error.localizedDescription.contains("signed in"))
    }

    func testCheckInAlreadyCheckedIn() {
        let error = CheckInError.alreadyCheckedIn
        XCTAssertTrue(error.localizedDescription.contains("already"))
    }

    // MARK: - NetworkError

    func testNetworkErrorMaxRetries() {
        let error = NetworkError.maxRetriesExceeded
        XCTAssertTrue(error.localizedDescription.contains("multiple attempts"))
    }

    func testNetworkErrorOffline() {
        let error = NetworkError.offline
        XCTAssertTrue(error.localizedDescription.contains("offline"))
    }

    func testNetworkErrorDeadlineExceededHasDescription() {
        XCTAssertNotNil(NetworkError.deadlineExceeded.errorDescription)
    }

    // MARK: - Background budget (iOS loop 6)

    /// Per-request timeout plus the overall deadline must leave headroom inside
    /// the ~30s iOS grants a background notification action.
    func testTimeoutsFitTheBackgroundBudget() {
        XCTAssertLessThanOrEqual(EdgeFunctionsClient.requestTimeout, 15)
        XCTAssertLessThan(NetworkRetry.backgroundActionBudget, 30)
        XCTAssertGreaterThanOrEqual(NetworkRetry.backgroundActionBudget, EdgeFunctionsClient.requestTimeout)
    }

    func testWithDeadlineReturnsAFastResult() async throws {
        let value = try await NetworkRetry.withDeadline(Date().addingTimeInterval(5)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testWithNilDeadlineRunsUnbounded() async throws {
        let value = try await NetworkRetry.withDeadline(nil) { "ok" }
        XCTAssertEqual(value, "ok")
    }

    func testWithDeadlineThrowsDeadlineExceededForASlowOperation() async {
        let start = Date()
        do {
            _ = try await NetworkRetry.withDeadline(Date().addingTimeInterval(0.2)) { () async throws -> Int in
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return 1
            }
            XCTFail("expected deadlineExceeded")
        } catch NetworkError.deadlineExceeded {
            // The slow operation was cancelled rather than awaited to completion.
            XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testWithPastDeadlineThrowsWithoutRunning() async {
        let ran = LockedFlag()
        do {
            try await NetworkRetry.withDeadline(Date().addingTimeInterval(-1)) { ran.set() }
            XCTFail("expected deadlineExceeded")
        } catch NetworkError.deadlineExceeded {
            XCTAssertFalse(ran.value)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testOperationErrorWinsOverDeadline() async {
        do {
            _ = try await NetworkRetry.withDeadline(Date().addingTimeInterval(5)) { () async throws -> Int in
                throw NetworkError.offline
            }
            XCTFail("expected offline")
        } catch NetworkError.offline {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// Cancelling the caller during the backoff sleep must stop the retry loop
    /// (it used to `try?` the sleep and fire the next attempt immediately).
    func testRetryLoopPropagatesCancellation() async {
        let attempts = LockedCounter()
        let task = Task {
            try await NetworkRetry.execute(maxAttempts: 3, initialDelay: 5) { () async throws -> Int in
                attempts.increment()
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let result = await task.result
        switch result {
        case .success:
            XCTFail("expected cancellation")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        XCTAssertEqual(attempts.value, 1)
    }

    // MARK: - SubscriptionError

    func testSubscriptionVerificationFailed() {
        let underlying = NSError(domain: "StoreKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Verification failed"])
        let error = SubscriptionError.verificationFailed(underlying)
        XCTAssertTrue(error.localizedDescription.contains("verification"))
    }

    func testSubscriptionPurchaseFailed() {
        let error = SubscriptionError.purchaseFailed
        XCTAssertTrue(error.localizedDescription.contains("completed"))
    }
}

/// Tiny thread-safe helpers for the async NetworkRetry tests.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
