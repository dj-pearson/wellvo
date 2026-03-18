import XCTest
@testable import Wellvo

/// Tests for WellvoError centralized error handling
final class ErrorHandlingTests: XCTestCase {

    // MARK: - WellvoError

    func testNetworkErrorDescription() {
        let underlyingError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let error = WellvoError.network(underlyingError)
        XCTAssertTrue(error.localizedDescription.contains("Network error"))
    }

    func testAuthErrorDescription() {
        let error = WellvoError.auth("Session expired")
        XCTAssertEqual(error.localizedDescription, "Session expired")
    }

    func testNotFoundErrorDescription() {
        let error = WellvoError.notFound("Family")
        XCTAssertEqual(error.localizedDescription, "Family not found.")
    }

    func testServerErrorDescription() {
        let error = WellvoError.serverError("Internal server error")
        XCTAssertTrue(error.localizedDescription.contains("Server error"))
    }

    func testOfflineErrorDescription() {
        let error = WellvoError.offline
        XCTAssertTrue(error.localizedDescription.contains("offline"))
    }

    func testUnknownErrorDescription() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        let error = WellvoError.unknown(underlying)
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
