import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Supabase

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated
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

    // Phone OTP fields
    @Published var phoneNumber = ""
    @Published var otpCode = ""
    @Published var isAwaitingOTP = false

    // Password reset
    @Published var isResettingPassword = false
    @Published var resetPasswordMessage: String?

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
    private var lockoutTimer: Task<Void, Never>?
    private var otpVerifyAttempts: Int = 0
    private static let maxOTPAttempts = 5

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

    init() {
        Task {
            await checkSession()
            listenForAuthStateChanges()
            await checkAppleCredentialRevocation()
            registerForAppleRevocationNotification()
        }
    }

    deinit {
        authStateTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Session Management

    func checkSession() async {
        do {
            if let user = try await AuthService.shared.currentSession() {
                currentUser = user
                authState = .authenticated
                // Drive the last-seen heartbeat only while signed in.
                HeartbeatService.shared.start()
            } else {
                authState = .unauthenticated
                HeartbeatService.shared.stop()
            }
        } catch {
            authState = .unauthenticated
            HeartbeatService.shared.stop()
        }
    }

    /// Listen for Supabase auth state changes (token refresh, session expiry)
    private func listenForAuthStateChanges() {
        authStateTask = Task {
            for await (event, _) in SupabaseService.shared.client.auth.authStateChanges {
                switch event {
                case .signedIn:
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
            errorMessage = "Couldn't start a secure sign-in. Please try again."
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
                errorMessage = "Invalid Apple credential"
                isLoading = false
                return
            }
            guard let rawNonce = currentRawNonce else {
                errorMessage = "Sign-in security check failed. Please try again."
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

    @Published var hasLinkedApple = false
    @Published var isLinkingApple = false
    @Published var linkAppleMessage: String?

    /// Check whether the current user already has a linked Apple identity.
    func checkAppleLinkStatus() async {
        hasLinkedApple = await AuthService.shared.hasLinkedAppleID()
    }

    /// Configure an Apple Sign-In request for identity linking (reuses nonce logic).
    func configureAppleLinkRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email]
        guard let rawNonce = Self.randomNonceString() else {
            currentRawNonce = nil
            linkAppleMessage = "Couldn't start a secure sign-in. Please try again."
            return
        }
        currentRawNonce = rawNonce
        request.nonce = Self.sha256(rawNonce)
    }

    /// Handle the Apple Sign-In result for identity linking.
    func linkAppleID(_ result: Result<ASAuthorization, Error>) async {
        isLinkingApple = true
        linkAppleMessage = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                linkAppleMessage = "Invalid Apple credential"
                isLinkingApple = false
                return
            }
            guard let rawNonce = currentRawNonce else {
                linkAppleMessage = "Security check failed. Please try again."
                isLinkingApple = false
                return
            }
            do {
                try await AuthService.shared.linkAppleID(credential: credential, rawNonce: rawNonce)
                currentRawNonce = nil
                hasLinkedApple = true
                linkAppleMessage = "Apple ID linked successfully!"
            } catch {
                linkAppleMessage = error.localizedDescription
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                linkAppleMessage = error.localizedDescription
            }
        }

        isLinkingApple = false
    }

    // MARK: - Email Auth

    func signInWithEmail() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
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
            errorMessage = error.localizedDescription
            password = "" // Clear password on failure
            recordFailedAttempt()
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
            errorMessage = "Please fill in all fields"
            return
        }
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        guard passwordMeetsPolicy else {
            errorMessage = "Password must be 10+ characters with an uppercase letter, a lowercase letter, and a number."
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
            errorMessage = error.localizedDescription
            password = "" // Clear password on failure
            recordFailedAttempt()
        }

        isLoading = false
    }

    // MARK: - Phone OTP Auth

    func sendPhoneOTP() async {
        let cleaned = phoneNumber.filter(\.isNumber)
        guard cleaned.count >= 10 else {
            errorMessage = "Please enter a valid phone number"
            return
        }
        guard !isLockedOut() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.sendPhoneOTP(phone: phoneNumber)
            isAwaitingOTP = true
            otpVerifyAttempts = 0
        } catch {
            errorMessage = "Could not send verification code. Please try again."
            recordFailedAttempt()
        }

        isLoading = false
    }

    func verifyPhoneOTP() async {
        guard otpCode.count == 6 else {
            errorMessage = "Please enter the 6-digit code"
            return
        }
        guard !isLockedOut() else { return }

        otpVerifyAttempts += 1
        if otpVerifyAttempts > Self.maxOTPAttempts {
            errorMessage = "Too many attempts. Please request a new code."
            isAwaitingOTP = false
            otpCode = ""
            otpVerifyAttempts = 0
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            currentUser = try await AuthService.shared.verifyPhoneOTP(phone: phoneNumber, code: otpCode)
            authState = .authenticated
            resetFailedAttempts()
            clearFormFields()
            await checkBiometricSetupPrompt()
        } catch {
            errorMessage = "Invalid code. Please try again. (\(Self.maxOTPAttempts - otpVerifyAttempts) attempts remaining)"
            otpCode = ""
            recordFailedAttempt()
        }

        isLoading = false
    }

    // MARK: - Password Reset

    func sendPasswordReset() async {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email address"
            return
        }
        guard isValidEmail(email) else {
            // Don't show the "link sent" success for an obviously-wrong address —
            // the user would wait for an email that can never arrive.
            errorMessage = "Please enter a valid email address"
            return
        }

        isResettingPassword = true
        errorMessage = nil
        resetPasswordMessage = nil

        do {
            try await AuthService.shared.resetPassword(email: email)
            // Always show same message to avoid user enumeration
            resetPasswordMessage = "If an account exists with that email, you'll receive a password reset link."
        } catch {
            // Don't reveal whether the email exists
            resetPasswordMessage = "If an account exists with that email, you'll receive a password reset link."
        }

        isResettingPassword = false
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
            await BiometricService.shared.reset()
            HeartbeatService.shared.stop()
            // Drop the shared check-in snapshot so Siri/widget/watch can't act
            // on a stale session after sign-out.
            SharedCheckInPublisher.clear()
            currentUser = nil
            authState = .unauthenticated
            biometricLocked = false
            clearFormFields()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Biometric Authentication

    /// Check if biometric should be presented on app resume.
    func checkBiometricOnResume() async {
        guard authState == .authenticated else { return }
        let biometric = BiometricService.shared
        guard await biometric.isEnabled, await biometric.isBiometricAvailable() else { return }

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
            errorMessage = "Your Apple ID access was revoked. Please sign in again."
        }
    }

    /// Listen for the system notification that fires when Apple credential is revoked.
    private func registerForAppleRevocationNotification() {
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.signOut()
                self?.errorMessage = "Your Apple ID access was revoked. Please sign in again."
            }
        }
    }

    // MARK: - Rate Limiting

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
        otpVerifyAttempts = 0
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
                authLockoutMessage = "Too many failed attempts. Try again in \(remaining)s."
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Helpers

    private func clearFormFields() {
        email = ""
        password = ""
        displayName = ""
        phoneNumber = ""
        otpCode = ""
        isAwaitingOTP = false
        resetPasswordMessage = nil
    }
}
