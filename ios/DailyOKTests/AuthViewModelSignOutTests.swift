import XCTest
@testable import DailyOK

/// Sign-out teardown (US-IOS141).
///
/// US-IOS140 was this bug: the server revoke and the entire local teardown sat
/// inside one do/catch, so a thrown revoke — any offline tap on "Sign out" —
/// skipped all of it. The user saw an error and stayed signed in, with the
/// shared Keychain tokens still published to the App Group, which is what the
/// widget, the watch and Siri authenticate with. On a device handed to someone
/// else, those surfaces could still check in as the previous user.
///
/// Nothing could have caught it. signOut drove five singletons directly, so a
/// test had no way to observe whether any of them were touched. These tests
/// exist because the failure was invisible, not because the fix was subtle.
@MainActor
final class AuthViewModelSignOutTests: XCTestCase {

    /// Records which teardown steps ran, so a test can assert on the set rather
    /// than on five separate flags.
    private final class TeardownLog {
        var biometricReset = false
        var heartbeatStopped = false
        var reconcileLatchReset = false
        var sharedSessionCleared = false

        var everythingRan: Bool {
            biometricReset && heartbeatStopped && reconcileLatchReset && sharedSessionCleared
        }
    }

    private struct RevokeFailed: Error {}

    private func dependencies(
        log: TeardownLog,
        revoke: @escaping @MainActor () async throws -> Void
    ) -> SignOutDependencies {
        SignOutDependencies(
            revokeServerSession: revoke,
            resetBiometric: { log.biometricReset = true },
            stopHeartbeat: { log.heartbeatStopped = true },
            resetReconcileLatch: { log.reconcileLatchReset = true },
            clearSharedSession: { log.sharedSessionCleared = true }
        )
    }

    /// `bootstrap: false` — the real init starts a network Task (session check,
    /// Apple credential state) that would race these assertions.
    private func makeViewModel(_ deps: SignOutDependencies) -> AuthViewModel {
        let viewModel = AuthViewModel(bootstrap: false)
        viewModel.signOutDependencies = deps
        viewModel.authState = .authenticated
        return viewModel
    }

    // MARK: - The regression

    func testTeardownRunsEvenWhenTheServerRevokeThrows() async {
        let log = TeardownLog()
        let viewModel = makeViewModel(dependencies(log: log) { throw RevokeFailed() })

        await viewModel.signOut()

        XCTAssertTrue(
            log.sharedSessionCleared,
            "Shared Keychain tokens must be cleared even when the revoke fails — the widget, watch and Siri authenticate with them."
        )
        XCTAssertTrue(log.reconcileLatchReset)
        XCTAssertTrue(log.biometricReset)
        XCTAssertTrue(log.heartbeatStopped)
        XCTAssertEqual(viewModel.authState, .unauthenticated)
        XCTAssertNil(viewModel.currentUser)
    }

    /// A failed revoke is not a failed sign-out. Locally the user IS signed out,
    /// so showing them an error would be telling them something untrue.
    func testAFailedRevokeIsNotSurfacedAsAnError() async {
        let log = TeardownLog()
        let viewModel = makeViewModel(dependencies(log: log) { throw RevokeFailed() })

        await viewModel.signOut()

        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - The success path, so the two cannot diverge

    func testTeardownRunsWhenTheServerRevokeSucceeds() async {
        let log = TeardownLog()
        let viewModel = makeViewModel(dependencies(log: log) { })

        await viewModel.signOut()

        XCTAssertTrue(log.everythingRan)
        XCTAssertEqual(viewModel.authState, .unauthenticated)
        XCTAssertNil(viewModel.currentUser)
    }

    /// The whole point: the two paths differ only in whether the revoke landed.
    func testSuccessAndFailurePathsTearDownIdentically() async {
        let succeeded = TeardownLog()
        await makeViewModel(dependencies(log: succeeded) { }).signOut()

        let failed = TeardownLog()
        await makeViewModel(dependencies(log: failed) { throw RevokeFailed() }).signOut()

        XCTAssertEqual(succeeded.biometricReset, failed.biometricReset)
        XCTAssertEqual(succeeded.heartbeatStopped, failed.heartbeatStopped)
        XCTAssertEqual(succeeded.reconcileLatchReset, failed.reconcileLatchReset)
        XCTAssertEqual(succeeded.sharedSessionCleared, failed.sharedSessionCleared)
        XCTAssertTrue(succeeded.everythingRan)
        XCTAssertTrue(failed.everythingRan)
    }

    /// Form fields are cleared so the next person to open the app does not find
    /// the previous user's email sitting in the sign-in box.
    func testFormFieldsAreClearedOnSignOut() async {
        let log = TeardownLog()
        let viewModel = makeViewModel(dependencies(log: log) { throw RevokeFailed() })
        viewModel.email = "someone@example.com"
        viewModel.password = "hunter2"
        viewModel.phoneNumber = "+15551234567"

        await viewModel.signOut()

        XCTAssertEqual(viewModel.email, "")
        XCTAssertEqual(viewModel.password, "")
        XCTAssertEqual(viewModel.phoneNumber, "")
    }
}
