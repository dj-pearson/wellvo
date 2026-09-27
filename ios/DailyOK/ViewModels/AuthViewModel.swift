import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import os
import Supabase

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated
}

/// The collaborators `AuthViewModel.signOut` tears down.
///
/// Exists so the teardown can be asserted (US-IOS141). US-IOS140 was a bug where
/// a thrown server revoke skipped every one of these — including clearing the
/// shared Keychain tokens the widget, watch and Siri authenticate with — and
/// nothing could have caught it, because signOut reached five singletons
/// directly and a test had no way to observe any of them.
///
/// Deliberately narrow. This is the sign-out path, not a dependency container
/// for the whole view model.
struct SignOutDependencies {
    /// Runs BEFORE the revoke — it needs the session to know whose token row to
    /// deactivate (US-IOS142).
    var deactivatePushToken: @MainActor () async -> Void
    var revokeServerSession: @MainActor () async throws -> Void
    var resetBiometric: @MainActor () async -> Void
    var stopHeartbeat: @MainActor () -> Void
    var resetReconcileLatch: @MainActor () -> Void
    var clearSharedSession: @MainActor () -> Void

    @MainActor
    static var live: SignOutDependencies {
        SignOutDependencies(
            deactivatePushToken: {
                await PushNotificationService.shared.deactivateCurrentDeviceToken()
                // Same reason, Live Activity tokens: before the revoke, while
                // the session can still say whose rows they are.
                await LiveActivityTokenService.shared.deactivateAll()
            },
            revokeServerSession: { try await AuthService.shared.signOut() },
            resetBiometric: { await BiometricService.shared.reset() },
            stopHeartbeat: { HeartbeatService.shared.stop() },
            resetReconcileLatch: { SubscriptionService.shared.resetReconcileLatch() },
            clearSharedSession: {
                SharedCheckInPublisher.clear()
                // The owner widget (incl. the Lock Screen accessory) and any
                // escalation Live Activity show the family's names, statuses
                // and a receiver's phone number — none of it may outlive the
                // session on a shared, handed-down or sold phone.
                SharedOwnerPublisher.clear()
                EscalationActivityManager.endAll()
                LiveActivityTokenService.shared.reset()
            }
        )
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var currentUser: AppUser?
    @Published var errorMessage: String?
    @Published var isLoading = false

    // Sign-up fields
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""

    // Add an email (accounts created with the retired phone sign-in)
    /// Where a phone-only account is in adding an email. `.hidden` = nothing
    /// to show (the account has an email, or the user chose "Not now").
    @Published var addEmailStage: AddEmailStage = .hidden
    @Published var addEmailAddress = ""
    @Published var addEmailCode = ""
    @Published var addEmailError: String?
    @Published var isAddingEmail = false
    /// "Not now" lasts until the next launch: asked once per launch, never nagged
    /// mid-task. In memory on purpose — a phone-only account should be asked
    /// again, since losing the session means losing the account.
    private var addEmailDeferredThisLaunch = false

    enum AddEmailStage: Equatable {
        case hidden
        case enterEmail   // asking for the address
        case enterCode    // code sent; waiting for the 6 digits (or the link)
        case done
    }

    // Password reset
    @Published var isResettingPassword = false
    @Published var resetPasswordMessage: String?
    /// Where the user is in the reset flow. The emailed LINK is not usable by
    /// this app (dailyok.net has no auth callback route), so recovery runs on the
    /// 6-digit code that arrives in the same email.
    @Published var resetStage: PasswordResetStage = .request
    @Published var recoveryCode = ""
    @Published var newPassword = ""

    enum PasswordResetStage {
        case request      // asking for the email address
        case enterCode    // email sent; user types the 6-digit code
        case setPassword  // code accepted; a session exists, take the new password
        case done
    }

    // Biometric
    @Published var showBiometricPrompt = false
    @Published var biometricLocked = false

    // Rate limiting
    @Published var authLockoutMessage: String?
    @Published var authLockoutSecondsRemaining: Int = 0
    private var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: "auth_failed_attempts") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_failed_attempts") }
    }
    private var lockoutUntil: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: "auth_lockout_until")
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "auth_lockout_until")
        }
    }
    private var lastFailureAt: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: "auth_last_failure_at")
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "auth_last_failure_at")
        }
    }

    /// Failures older than an hour no longer count toward a lockout.
    nonisolated static func failuresHaveDecayed(lastFailureAt: Date?, now: Date = Date()) -> Bool {
        guard let lastFailureAt else { return false }
        return now.timeIntervalSince(lastFailureAt) > 60 * 60
    }
    private var lockoutTimer: Task<Void, Never>?

    /// The raw nonce generated for the current Apple Sign-In attempt.
    /// Stored in Keychain so it survives view recreation and SwiftUI lifecycle events.
    private var currentRawNonce: String? {
        get { KeychainService.load(key: "apple_signin_nonce") }
        set {
            if let newValue {
                _ = KeychainService.save(key: "apple_signin_nonce", value: newValue)
            } else {
                KeychainService.delete(key: "apple_signin_nonce")
            }
            // Migrate: remove old UserDefaults storage
            UserDefaults.standard.removeObject(forKey: "apple_signin_nonce")
        }
    }

    /// Supabase auth state listener handle
    private var authStateTask: Task<Void, Never>?
    /// Token for the block-based Apple-revocation observer. `removeObserver(self)`
    /// does NOT remove block observers (self isn't the observer — this token is),
    /// so it must be retained and removed explicitly.
    private var appleRevocationObserver: NSObjectProtocol?

    /// Overridden by tests; nil means the live singletons.
    var signOutDependencies: SignOutDependencies?

    /// `bootstrap: false` skips the session/Apple-credential work below, which is
    /// network-bound and would race a test's assertions. Defaults to true, so
    /// every app call site is unchanged.
    init(bootstrap: Bool = true) {
        guard bootstrap else { return }
        Task {
            await checkSession()
            listenForAuthStateChanges()
            await checkAppleCredentialRevocation()
            registerForAppleRevocationNotification()
        }
    }

    deinit {
        authStateTask?.cancel()
        if let appleRevocationObserver {
            NotificationCenter.default.removeObserver(appleRevocationObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Session Management

    func checkSession() async {
        // A verified password-reset code creates a real session (GoTrue signs
        // the user in), but the reset isn't finished until a new password is
        // set. Adopting it here used to swap the reset sheet for the app the
        // moment the code was accepted, so the password never changed.
        guard !holdsSessionForPasswordReset else { return }
        do {
            if let user = try await AuthService.shared.currentSession() {
                currentUser = user
                authState = .authenticated
                // Drive the last-seen heartbeat only while signed in.
                HeartbeatService.shared.start()
                await checkAccountHasEmail()
            } else {
                authState = .unauthenticated
                HeartbeatService.shared.stop()
            }
        } catch {
            // A thrown error means the auth session may still be valid but the
            // profile fetch failed transiently (network blip on foreground /
            // resume). Do NOT sign the user out over that — keep the existing
            // authenticated session if we already have a user. On a cold start
            // with no profile yet, stay signed in only when the failure is the
            // network and a session is stored: that is a receiver opening the
            // app offline, who needs the I'm OK button (and its offline queue),
            // not the sign-in screen. Routing uses the cached role.
            if Self.keepsSessionAfterFailedCheck(
                hasLoadedUser: currentUser != nil,
                hasStoredSession: AuthService.shared.hasStoredSession,
                isConnectivityError: AuthService.isConnectivityError(error)
            ) {
                authState = .authenticated
            } else {
                authState = .unauthenticated
                HeartbeatService.shared.stop()
            }
        }
    }

    /// Whether a failed session check keeps the user signed in (see checkSession).
    nonisolated static func keepsSessionAfterFailedCheck(
        hasLoadedUser: Bool,
        hasStoredSession: Bool,
        isConnectivityError: Bool
    ) -> Bool {
        hasLoadedUser || (hasStoredSession && isConnectivityError)
    }

    /// True while the password-reset sheet owns the session its code created:
    /// the code has been accepted (or is being checked) and no new password is
    /// set yet. Nothing may treat the user as signed in until they finish.
    var holdsSessionForPasswordReset: Bool {
        Self.resetHoldsSession(resetStage)
    }

    nonisolated static func resetHoldsSession(_ stage: PasswordResetStage) -> Bool {
        switch stage {
        case .enterCode, .setPassword: return true
        case .request, .done: return false
        }
    }

    /// Listen for Supabase auth state changes (token refresh, session expiry)
    private func listenForAuthStateChanges() {
        authStateTask = Task {
            for await (event, _) in SupabaseService.shared.client.auth.authStateChanges {
                switch event {
                case .signedIn:
                    // checkSession itself ignores the session a password-reset
                    // code creates until the new password is set.
                    if currentUser == nil {
                        await checkSession()
                    }
                case .signedOut, .userDeleted:
                    currentUser = nil
                    authState = .unauthenticated
                    clearFormFields()
                case .tokenRefreshed:
                    // Supabase access tokens last ~1h. Re-mirror the refreshed
                    // token into the shared Keychain so the Notification Service
                    // Extension, widgets, Siri, and watch keep a valid token —
                    // otherwise confirm-delivery / background check-ins start
                    // 401ing after the first refresh (US-IOS084).
                    await SupabaseService.shared.syncAccessTokenToExtension()
                    // An offline launch kept the stored session without a
                    // profile; the first successful refresh means the network
                    // is back, so load it now rather than at next foreground.
                    if currentUser == nil, authState == .authenticated {
                        await checkSession()
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Apple Sign-In

    /// Prepare the Apple Sign-In request.
    /// Call this from the SignInWithAppleButton's `onRequest` closure.
    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        guard let rawNonce = Self.randomNonceString() else {
            // CSPRNG failed: abort this attempt rather than fall back to a
            // non-cryptographic UUID nonce. Leaving currentRawNonce nil makes the
            // result handler reject the credential and ask the user to retry.
            currentRawNonce = nil
            errorMessage = String(localized: "Couldn't start a secure sign-in. Please try again.")
            return
        }
        currentRawNonce = rawNonce
        request.nonce = Self.sha256(rawNonce)
    }

    // MARK: - Nonce Helpers (synchronous, no actor hop needed)

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Returns a cryptographically-random nonce, or `nil` if the system CSPRNG
    /// fails. Callers must treat `nil` as a fatal-for-this-attempt error and
    /// retry — never substitute a non-cryptographic value (a UUID nonce would
    /// weaken the replay protection Apple Sign-In relies on).
    private static func randomNonceString(length: Int = 32) -> String? {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else { return nil }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    func signInWithApple(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = String(localized: "Invalid Apple credential")
                isLoading = false
                return
            }
            guard let rawNonce = currentRawNonce else {
                errorMessage = String(localized: "Sign-in security check failed. Please try again.")
                isLoading = false
                return
            }
            do {
                currentUser = try await AuthService.shared.signInWithApple(credential: credential, rawNonce: rawNonce)
                currentRawNonce = nil
                authState = .authenticated
                clearFormFields()
                await checkBiometricSetupPrompt()
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            // Don't show error if user cancelled
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Link Apple ID

    enum AppleLinkState: Equatable {
        /// Not checked yet, or the check failed (offline). Settings shows
        /// neither "Linked" nor the link button.
        case unknown
        case linked
        case notLinked
    }

    @Published var appleLinkState: AppleLinkState = .unknown
    @Published var isLinkingApple = false
    @Published var linkAppleMessage: String?
    /// Whether `linkAppleMessage` reports success (green) or a problem.
    @Published var linkAppleMessageIsSuccess = false

    var hasLinkedApple: Bool { appleLinkState == .linked }

    /// Check whether the current user already has a linked Apple identity.
    /// A failed check leaves a known state alone rather than flipping a linked
    /// account back to "Link your Apple ID".
    func checkAppleLinkStatus() async {
        if let linked = await AuthService.shared.appleIDLinkStatus() {
            appleLinkState = linked ? .linked : .notLinked
        }
    }

    /// Drop a stale result line when the user leaves Settings.
    func clearAppleLinkMessage() {
        if !isLinkingApple { linkAppleMessage = nil }
    }

    /// Plain words for a failed link (the raw error read "Edge function error
    /// 409: {\"error\":…}").
    nonisolated static func appleLinkFailureMessage(_ error: Error) -> String {
        if let http = error as? EdgeFunctionsClient.HTTPError {
            switch http.status {
            case 409:
                return String(localized: "This Apple ID is already used by another Daily OK account.")
            case 400, 401:
                return String(localized: "Apple couldn't confirm this sign-in. Please try again.")
            default:
                return String(localized: "Couldn't link your Apple ID right now. Please try again later.")
            }
        }
        if error is URLError {
            return String(localized: "You're offline. Check your connection and try again.")
        }
        return String(localized: "Couldn't link your Apple ID right now. Please try again later.")
    }

    /// Configure an Apple Sign-In request for identity linking (reuses nonce logic).
    func configureAppleLinkRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email]
        guard let rawNonce = Self.randomNonceString() else {
            currentRawNonce = nil
            linkAppleMessage = String(localized: "Couldn't start a secure sign-in. Please try again.")
            return
        }
        currentRawNonce = rawNonce
        request.nonce = Self.sha256(rawNonce)
    }

    /// Handle the Apple Sign-In result for identity linking.
    func linkAppleID(_ result: Result<ASAuthorization, Error>) async {
        isLinkingApple = true
        linkAppleMessage = nil
        linkAppleMessageIsSuccess = false

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                linkAppleMessage = String(localized: "Invalid Apple credential")
                isLinkingApple = false
                return
            }
            guard let rawNonce = currentRawNonce else {
                linkAppleMessage = String(localized: "Security check failed. Please try again.")
                isLinkingApple = false
                return
            }
            do {
                try await AuthService.shared.linkAppleID(credential: credential, rawNonce: rawNonce)
                currentRawNonce = nil
                appleLinkState = .linked
                linkAppleMessageIsSuccess = true
                linkAppleMessage = String(localized: "Apple ID linked. You can now use Sign in with Apple.")
            } catch {
                Log.auth.error("Link Apple ID failed: \(error.localizedDescription, privacy: .public)")
                linkAppleMessage = Self.appleLinkFailureMessage(error)
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                linkAppleMessage = String(localized: "Sign in with Apple didn't finish. Please try again.")
            }
        }

        isLinkingApple = false
    }

    // MARK: - Email Auth

    func signInWithEmail() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "Please fill in all fields")
            return
        }
        guard !isLockedOut() else { return }

        isLoading = true
        errorMessage = nil

        do {
            currentUser = try await AuthService.shared.signInWithEmail(email: email, password: password)
            authState = .authenticated
            resetFailedAttempts()
            clearFormFields()
            await checkBiometricSetupPrompt()
        } catch {
            if AuthService.isConnectivityError(error) {
                // Not a wrong password: keep what they typed and don't count it.
                errorMessage = Self.offlineMessage
            } else {
                errorMessage = error.localizedDescription
                password = "" // Clear password on failure
                recordFailedAttempt()
            }
        }

        isLoading = false
    }

    /// Lightweight RFC-ish email format check so we don't tell the user a reset
    /// link is on the way (or attempt a sign-up) for an obviously-invalid address.
    func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil
    }

    /// The displayed sign-up password policy, enforced client-side.
    var passwordMeetsPolicy: Bool { PasswordStrength.meetsPolicy(password) }

    func signUpWithEmail() async {
        guard !email.isEmpty, !password.isEmpty, !displayName.isEmpty else {
            errorMessage = String(localized: "Please fill in all fields")
            return
        }
        guard isValidEmail(email) else {
            errorMessage = String(localized: "Please enter a valid email address")
            return
        }
        guard passwordMeetsPolicy else {
            errorMessage = String(localized: "Password must be 10+ characters with an uppercase letter, a lowercase letter, and a number.")
            return
        }
        guard !isLockedOut() else { return }

        isLoading = true
        errorMessage = nil

        do {
            currentUser = try await AuthService.shared.signUpWithEmail(
                email: email,
                password: password,
                displayName: displayName
            )
            authState = .authenticated
            resetFailedAttempts()
            clearFormFields()
            await checkBiometricSetupPrompt()
        } catch {
            if AuthService.isConnectivityError(error) {
                errorMessage = Self.offlineMessage
            } else {
                errorMessage = error.localizedDescription
                password = "" // Clear password on failure
                recordFailedAttempt()
            }
        }

        isLoading = false
    }

    /// Shown when the server never answered. Such a failure says nothing about
    /// the password or code, so it never counts toward the lockout.
    static let offlineMessage = String(localized: "Couldn't reach Daily OK. Check your connection and try again.")

    // MARK: - Add an email (phone sign-in retired)

    /// Offer "Add an email" to an account that has none. Phone-number sign-in
    /// is gone (server-sent SMS codes would need A2P 10DLC registration), so a
    /// phone-only account that signs out, or loses its session, has no way back
    /// in. While the session lasts, the app asks for an email once per launch.
    func checkAccountHasEmail() async {
        guard authState == .authenticated,
              addEmailStage == .hidden,
              !addEmailDeferredThisLaunch,
              !holdsSessionForPasswordReset else { return }
        if await AuthService.shared.signedInAccountLacksEmail() {
            addEmailError = nil
            addEmailStage = .enterEmail
        }
    }

    /// "Not now": close the prompt until the next launch.
    func deferAddEmail() {
        addEmailDeferredThisLaunch = true
        addEmailStage = .hidden
        addEmailCode = ""
        addEmailError = nil
        isAddingEmail = false
    }

    func sendAddEmailCode() async {
        let address = addEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(address) else {
            addEmailError = String(localized: "Please enter a valid email address")
            return
        }
        isAddingEmail = true
        addEmailError = nil
        do {
            try await AuthService.shared.requestAddEmail(address)
            addEmailCode = ""
            addEmailStage = .enterCode
        } catch {
            addEmailError = Self.addEmailFailureMessage(error)
        }
        isAddingEmail = false
    }

    func confirmAddEmailCode() async {
        let digits = addEmailCode.filter(\.isNumber)
        guard digits.count == 6 else {
            addEmailError = String(localized: "Enter the 6-digit code from your email.")
            return
        }
        isAddingEmail = true
        addEmailError = nil
        do {
            try await AuthService.shared.confirmAddedEmail(addEmailAddress, code: digits)
            addEmailStage = .done
            await refreshCurrentUserQuietly()
        } catch {
            addEmailError = AuthService.isConnectivityError(error)
                ? Self.offlineMessage
                : String(localized: "That code is incorrect or has expired. Check the email, or send a new code.")
        }
        isAddingEmail = false
    }

    /// The user tapped the link in the email instead of typing the code.
    func checkAddedEmailByLink() async {
        isAddingEmail = true
        addEmailError = nil
        if await AuthService.shared.refreshAddedEmailStatus() {
            addEmailStage = .done
            await refreshCurrentUserQuietly()
        } else {
            addEmailError = String(localized: "Not confirmed yet. Tap the link in the email, or type the code.")
        }
        isAddingEmail = false
    }

    /// Back from the code step to fix the address.
    func editAddEmailAddress() {
        addEmailCode = ""
        addEmailError = nil
        addEmailStage = .enterEmail
    }

    /// Close the prompt after success.
    func finishAddEmail() {
        addEmailStage = .hidden
        addEmailCode = ""
        addEmailError = nil
    }

    private func refreshCurrentUserQuietly() async {
        if let user = try? await AuthService.shared.currentSession() {
            currentUser = user
        }
    }

    /// Plain words for a failed add-email request.
    static func addEmailFailureMessage(_ error: Error) -> String {
        if AuthService.isConnectivityError(error) { return offlineMessage }
        let text = error.localizedDescription.lowercased()
        if text.contains("already") && (text.contains("registered") || text.contains("exists") || text.contains("use")) {
            return String(localized: "That email is already used by another Daily OK account. Try a different one.")
        }
        if text.contains("rate") || text.contains("too many") || text.contains("seconds") {
            return String(localized: "Please wait a minute before asking for another code.")
        }
        return String(localized: "Couldn't send the code. Check the address and try again.")
    }

    // MARK: - Password Reset

    func sendPasswordReset() async {
        guard !email.isEmpty else {
            errorMessage = String(localized: "Please enter your email address")
            return
        }
        guard isValidEmail(email) else {
            // Don't show the "link sent" success for an obviously-wrong address —
            // the user would wait for an email that can never arrive.
            errorMessage = String(localized: "Please enter a valid email address")
            return
        }

        isResettingPassword = true
        errorMessage = nil
        resetPasswordMessage = nil

        do {
            try await AuthService.shared.resetPassword(email: email)
            // Always show same message to avoid user enumeration
            resetPasswordMessage = String(localized: "If an account exists with that email, we've sent a 6-digit code.")
        } catch {
            // Don't reveal whether the email exists
            resetPasswordMessage = String(localized: "If an account exists with that email, we've sent a 6-digit code.")
        }

        // Advance on BOTH branches. Which one we took is exactly the fact we are
        // refusing to disclose, so holding the code screen back on failure would
        // leak account existence through the UI after hiding it in the copy.
        resetStage = .enterCode
        isResettingPassword = false
    }

    /// Verify the 6-digit code from the reset email. On success GoTrue returns a
    /// session, which is what makes the password update below possible.
    func verifyRecoveryCode() async {
        let digits = recoveryCode.filter(\.isNumber)
        guard digits.count == 6 else {
            errorMessage = String(localized: "Enter the 6-digit code from your email.")
            return
        }

        isResettingPassword = true
        errorMessage = nil

        do {
            try await AuthService.shared.verifyRecoveryCode(email: email, code: digits)
            resetPasswordMessage = nil
            resetStage = .setPassword
        } catch {
            // A wrong or expired code IS safe to report plainly: the user already
            // proved they hold the address by receiving one.
            errorMessage = String(localized: "That code is incorrect or has expired. Request a new one.")
        }

        isResettingPassword = false
    }

    /// Set the new password on the session established by the code.
    func submitNewPassword() async {
        isResettingPassword = true
        errorMessage = nil

        do {
            try await AuthService.shared.updatePassword(newPassword)
            resetStage = .done
            resetPasswordMessage = String(localized: "Password updated. You're signed in.")
            newPassword = ""
            recoveryCode = ""
        } catch {
            errorMessage = AuthService.isConnectivityError(error)
                ? Self.offlineMessage
                : error.localizedDescription
        }

        isResettingPassword = false
    }

    /// "Done" on the reset confirmation: the new password is set, so the
    /// session the code created may now sign the user in.
    func finishPasswordReset() async {
        cancelPasswordReset()
        await checkSession()
        if authState == .authenticated {
            resetFailedAttempts()
            await checkBiometricSetupPrompt()
        }
    }

    /// Return the reset flow to its starting state (cancel, or start over after a
    /// code expires).
    func cancelPasswordReset() {
        let abandonedRecoverySession = resetStage == .setPassword
        resetStage = .request
        recoveryCode = ""
        newPassword = ""
        resetPasswordMessage = nil
        errorMessage = nil
        // Cancelling after the code was accepted leaves a signed-in session in
        // the Keychain for a password that was never changed. Drop it, so the
        // next launch doesn't quietly sign in with it.
        if abandonedRecoverySession {
            Task { await signOut() }
        }
    }

    func signOut() async {
        // Server-side revocation is best effort. It is a network call, so it
        // fails whenever the user happens to be offline — and every line below
        // used to sit inside the same `do`, so a failed revoke abandoned the
        // ENTIRE local teardown (US-IOS140). The user tapped "Sign out", saw an
        // error, and stayed signed in with:
        //   * the shared Keychain tokens still published, so the widget, watch
        //     and Siri could go on checking in as them — the one that matters,
        //     because those surfaces are reachable by whoever holds the device
        //     next
        //   * biometric still bound to the old account
        //   * the heartbeat still reporting them as active
        //   * the entitlement reconcile latch still closed, which
        //     resetReconcileLatch's own documentation says must not happen,
        //     because the next user to sign in on this device is then skipped
        //
        // Their intent is not ambiguous. Sign them out locally either way.
        let deps = signOutDependencies ?? .live

        // Before the revoke, while the session still identifies who to
        // deactivate: stop this device receiving the outgoing user's
        // notifications. Otherwise their check-in requests and family alerts keep
        // arriving on a phone that now belongs to someone else (US-IOS142).
        await deps.deactivatePushToken()

        do {
            try await deps.revokeServerSession()
        } catch {
            // Not surfaced to the user: locally they ARE signed out, and an
            // error here would say otherwise. The residual is that the refresh
            // token was not revoked server-side and stays valid until it
            // expires — worth knowing in the log, not worth blocking on.
            Log.auth.error("Server sign-out failed; clearing local session anyway: \(error.localizedDescription, privacy: .public)")
        }

        // Unconditional local teardown.
        await deps.resetBiometric()
        deps.stopHeartbeat()
        // Allow the next (possibly different) user to reconcile entitlements
        // within this same process launch.
        deps.resetReconcileLatch()
        // Drop the shared check-in snapshot so Siri/widget/watch can't act
        // on a stale session after sign-out.
        deps.clearSharedSession()
        currentUser = nil
        authState = .unauthenticated
        biometricLocked = false
        // The next account on this phone must not see this one's Apple link.
        appleLinkState = .unknown
        linkAppleMessage = nil
        linkAppleMessageIsSuccess = false
        // The add-email prompt belongs to the account that just left.
        addEmailStage = .hidden
        addEmailAddress = ""
        addEmailCode = ""
        addEmailError = nil
        addEmailDeferredThisLaunch = false
        clearFormFields()
    }

    // MARK: - Biometric Authentication

    /// Check if biometric should be presented on app resume.
    func checkBiometricOnResume() async {
        guard authState == .authenticated else { return }
        let biometric = BiometricService.shared
        guard await biometric.isEnabled, await biometric.isBiometricAvailable() else {
            // Lock is off, or can't be enforced on this device (no Face ID
            // enrolled): nothing to withhold behind. Open the gate and put the
            // tokens back so the widget, Siri and the watch work.
            if !SharedTokenGate.mayMirror {
                await SharedCheckInPublisher.republishTokensFromSession()
            }
            return
        }

        biometricLocked = true
        // Withhold the mirrored session from every out-of-process surface while
        // locked, so a widget / Siri / watch tap can't act as the user until
        // biometric auth succeeds. (Belt-and-suspenders with the background
        // withholding in DailyOKApp.)
        SharedCheckInPublisher.withholdTokens()
        await attemptBiometricUnlock()
    }

    /// Run the biometric prompt; on success, lift the lock and restore the
    /// mirrored session for out-of-process surfaces. Called on resume and from
    /// the lock screen's retry button.
    func attemptBiometricUnlock() async {
        let success = await BiometricService.shared.authenticate()
        biometricLocked = !success
        if success {
            await SharedCheckInPublisher.republishTokensFromSession()
        }
    }

    /// After first successful sign-in, check if we should offer biometric setup.
    func checkBiometricSetupPrompt() async {
        guard await BiometricService.shared.shouldPromptToEnable() else { return }
        showBiometricPrompt = true
    }

    func enableBiometric() async {
        await BiometricService.shared.setEnabled(true)
        // Turned on from inside the unlocked app: presence is already shown
        // for this session.
        SharedTokenGate.markUnlocked()
        NotificationCategories.register()
        showBiometricPrompt = false
    }

    func skipBiometric() async {
        await BiometricService.shared.setSkipped(true)
        showBiometricPrompt = false
    }

    // MARK: - Apple Credential Revocation

    /// Check on launch whether the Apple credential has been revoked.
    private func checkAppleCredentialRevocation() async {
        let isValid = await AuthService.shared.checkAppleCredentialStatus()
        if !isValid {
            await signOut()
            errorMessage = String(localized: "Your Apple ID access was revoked. Please sign in again.")
        }
    }

    /// Listen for the system notification that fires when Apple credential is revoked.
    private func registerForAppleRevocationNotification() {
        appleRevocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.signOut()
                self?.errorMessage = String(localized: "Your Apple ID access was revoked. Please sign in again.")
            }
        }
    }

    // MARK: - Rate Limiting

    /// Show a lockout that is still running from before (the countdown lives
    /// in UserDefaults) as soon as the sign-in screen appears, instead of only
    /// after a tap that silently does nothing.
    func refreshLockoutState() {
        _ = isLockedOut()
    }

    /// Check if auth is currently locked out. Returns true if locked.
    private func isLockedOut() -> Bool {
        if let until = lockoutUntil, until > Date() {
            startLockoutCountdown(until: until)
            return true
        }
        // Clear stale lockout
        if lockoutUntil != nil {
            lockoutUntil = nil
            authLockoutMessage = nil
            authLockoutSecondsRemaining = 0
        }
        return false
    }

    /// Record a failed auth attempt and apply lockout if threshold reached.
    private func recordFailedAttempt() {
        // Old failures decay: someone who mistyped five times last month is
        // not one wrong guess from a 5-minute lockout today.
        if Self.failuresHaveDecayed(lastFailureAt: lastFailureAt) {
            failedAttempts = 0
        }
        lastFailureAt = Date()
        failedAttempts += 1
        let count = failedAttempts

        if count >= 10 {
            let lockout = Date().addingTimeInterval(300) // 5 minutes
            lockoutUntil = lockout
            startLockoutCountdown(until: lockout)
        } else if count >= 5 {
            let lockout = Date().addingTimeInterval(30) // 30 seconds
            lockoutUntil = lockout
            startLockoutCountdown(until: lockout)
        }
    }

    /// Reset failed attempts on successful auth.
    private func resetFailedAttempts() {
        failedAttempts = 0
        lockoutUntil = nil
        authLockoutMessage = nil
        authLockoutSecondsRemaining = 0
        lockoutTimer?.cancel()
    }

    private func startLockoutCountdown(until date: Date) {
        lockoutTimer?.cancel()
        lockoutTimer = Task {
            while !Task.isCancelled {
                let remaining = Int(date.timeIntervalSinceNow)
                if remaining <= 0 {
                    authLockoutMessage = nil
                    authLockoutSecondsRemaining = 0
                    break
                }
                authLockoutSecondsRemaining = remaining
                authLockoutMessage = String(localized: "Too many failed attempts. Try again in \(remaining)s.")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Helpers

    private func clearFormFields() {
        email = ""
        password = ""
        displayName = ""
        resetPasswordMessage = nil
        resetStage = .request
        recoveryCode = ""
        newPassword = ""
    }
}
