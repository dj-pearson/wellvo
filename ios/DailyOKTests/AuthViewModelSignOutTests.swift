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
        var pushTokenDeactivated = false
        var biometricReset = false
        var heartbeatStopped = false
        var reconcileLatchReset = false
        var sharedSessionCleared = false

        var everythingRan: Bool {
            pushTokenDeactivated && biometricReset && heartbeatStopped
                && reconcileLatchReset && sharedSessionCleared
        }
    }

    private struct RevokeFailed: Error {}

    private func dependencies(
        log: TeardownLog,
        revoke: @escaping @MainActor () async throws -> Void
    ) -> SignOutDependencies {
        SignOutDependencies(
            deactivatePushToken: { log.pushTokenDeactivated = true },
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
        XCTAssertTrue(
            log.pushTokenDeactivated,
            "The outgoing user's device token must be deactivated, or their check-in requests keep arriving on a phone someone else now holds."
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

        XCTAssertEqual(succeeded.pushTokenDeactivated, failed.pushTokenDeactivated)
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
        viewModel.addEmailAddress = "new@example.com"
        viewModel.addEmailStage = .enterCode

        await viewModel.signOut()

        XCTAssertEqual(viewModel.email, "")
        XCTAssertEqual(viewModel.password, "")
        // The add-email prompt belonged to the account that signed out.
        XCTAssertEqual(viewModel.addEmailAddress, "")
        XCTAssertEqual(viewModel.addEmailStage, .hidden)
    }
}

// MARK: - Sign-in, password reset and offline launch

/// Auth & onboarding deep dive (2026-09-27).
@MainActor
final class AuthFlowTests: XCTestCase {
    private final class Flag { var value = false }

    private func recordingSignOut(_ revoked: Flag) -> SignOutDependencies {
        SignOutDependencies(
            deactivatePushToken: {},
            revokeServerSession: { revoked.value = true },
            resetBiometric: {},
            stopHeartbeat: {},
            resetReconcileLatch: {},
            clearSharedSession: {}
        )
    }

    // MARK: Password reset keeps the auth UI until the new password is set

    /// Verifying the emailed code creates a real session (supabase-swift emits
    /// .signedIn). checkSession used to adopt it, ContentView swapped the reset
    /// sheet for the app, and the password was never changed.
    func testResetCodeSessionIsHeldUntilThePasswordIsSet() {
        XCTAssertFalse(AuthViewModel.resetHoldsSession(.request))
        XCTAssertTrue(AuthViewModel.resetHoldsSession(.enterCode))
        XCTAssertTrue(AuthViewModel.resetHoldsSession(.setPassword))
        XCTAssertFalse(AuthViewModel.resetHoldsSession(.done))
    }

    func testCheckSessionDoesNotSignInMidReset() async {
        let viewModel = AuthViewModel(bootstrap: false)
        viewModel.authState = .unauthenticated
        viewModel.resetStage = .setPassword

        // Returns before touching the network.
        await viewModel.checkSession()

        XCTAssertEqual(viewModel.authState, .unauthenticated)
        XCTAssertEqual(viewModel.resetStage, .setPassword)
    }

    /// Cancelling after the code was accepted drops the recovery session, so
    /// the next launch doesn't quietly sign in with a password never changed.
    func testCancellingAfterTheCodeSignsTheRecoverySessionOut() async {
        let revoked = Flag()
        let viewModel = AuthViewModel(bootstrap: false)
        viewModel.signOutDependencies = recordingSignOut(revoked)
        viewModel.resetStage = .setPassword

        viewModel.cancelPasswordReset()
        for _ in 0..<100 where !revoked.value { await Task.yield() }

        XCTAssertTrue(revoked.value)
        XCTAssertEqual(viewModel.resetStage, .request)
    }

    func testCancellingBeforeTheCodeDoesNotSignOut() async {
        let revoked = Flag()
        let viewModel = AuthViewModel(bootstrap: false)
        viewModel.signOutDependencies = recordingSignOut(revoked)
        viewModel.resetStage = .enterCode

        viewModel.cancelPasswordReset()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(revoked.value)
    }

    // MARK: Offline launch

    /// Access tokens last about an hour; a receiver opens the app once a day.
    /// An offline refresh used to read as "signed out".
    func testOfflineLaunchWithAStoredSessionStaysSignedIn() {
        XCTAssertTrue(AuthViewModel.keepsSessionAfterFailedCheck(
            hasLoadedUser: false, hasStoredSession: true, isConnectivityError: true))
        XCTAssertTrue(AuthViewModel.keepsSessionAfterFailedCheck(
            hasLoadedUser: true, hasStoredSession: true, isConnectivityError: false))
        // The server refused (or nothing is stored): sign-in screen.
        XCTAssertFalse(AuthViewModel.keepsSessionAfterFailedCheck(
            hasLoadedUser: false, hasStoredSession: true, isConnectivityError: false))
        XCTAssertFalse(AuthViewModel.keepsSessionAfterFailedCheck(
            hasLoadedUser: false, hasStoredSession: false, isConnectivityError: true))
    }

    func testConnectivityErrorsAreToldApartFromRefusals() {
        XCTAssertTrue(AuthService.isConnectivityError(URLError(.notConnectedToInternet)))
        XCTAssertTrue(AuthService.isConnectivityError(URLError(.timedOut)))
        XCTAssertTrue(AuthService.isConnectivityError(DailyOKError.network(URLError(.networkConnectionLost))))
        XCTAssertTrue(AuthService.isConnectivityError(DailyOKError.offline))
        XCTAssertFalse(AuthService.isConnectivityError(EdgeFunctionsClient.HTTPError(status: 400, body: "{}")))
        XCTAssertFalse(AuthService.isConnectivityError(DailyOKError.auth("Invalid login credentials")))
        XCTAssertFalse(AuthService.isConnectivityError(NSError(domain: "GoTrue", code: 400)))
    }

    // MARK: Lockout

    /// Five mistakes last month shouldn't leave someone one typo from a
    /// 5-minute lockout today.
    func testOldFailuresDecay() {
        let now = Date()
        XCTAssertFalse(AuthViewModel.failuresHaveDecayed(lastFailureAt: nil, now: now))
        XCTAssertFalse(AuthViewModel.failuresHaveDecayed(lastFailureAt: now.addingTimeInterval(-600), now: now))
        XCTAssertTrue(AuthViewModel.failuresHaveDecayed(lastFailureAt: now.addingTimeInterval(-3_700), now: now))
    }

    // MARK: Accounts without an email (phone sign-in retired)

    /// A phone-only account has no email; it is the one asked to add one.
    func testAccountWithoutEmailIsAskedToAddOne() {
        XCTAssertTrue(AuthService.accountLacksEmail(email: nil))
        XCTAssertTrue(AuthService.accountLacksEmail(email: ""))
        XCTAssertTrue(AuthService.accountLacksEmail(email: "  "))
        XCTAssertFalse(AuthService.accountLacksEmail(email: "mom@example.com"))
    }

    /// "Not now" closes the prompt without touching the rest of the session.
    func testNotNowClosesTheAddEmailPrompt() {
        let viewModel = AuthViewModel(bootstrap: false)
        viewModel.addEmailStage = .enterEmail
        viewModel.addEmailError = "x"
        viewModel.deferAddEmail()
        XCTAssertEqual(viewModel.addEmailStage, .hidden)
        XCTAssertNil(viewModel.addEmailError)
    }
}
