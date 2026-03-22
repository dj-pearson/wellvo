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

    /// The raw nonce generated for the current Apple Sign-In attempt.
    private var currentRawNonce: String?

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
            } else {
                authState = .unauthenticated
            }
        } catch {
            authState = .unauthenticated
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
                    break // Session silently refreshed
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
    }

    // MARK: - Nonce Helpers (synchronous, no actor hop needed)

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
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
                authState = .authenticated
                clearFormFields()
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

    // MARK: - Email Auth

    func signInWithEmail() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            currentUser = try await AuthService.shared.signInWithEmail(email: email, password: password)
            authState = .authenticated
            clearFormFields()
        } catch {
            errorMessage = error.localizedDescription
            password = "" // Clear password on failure
        }

        isLoading = false
    }

    func signUpWithEmail() async {
        guard !email.isEmpty, !password.isEmpty, !displayName.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            currentUser = try await AuthService.shared.signUpWithEmail(
                email: email,
                password: password,
                displayName: displayName
            )
            authState = .authenticated
            clearFormFields()
        } catch {
            errorMessage = error.localizedDescription
            password = "" // Clear password on failure
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

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.sendPhoneOTP(phone: phoneNumber)
            isAwaitingOTP = true
        } catch {
            errorMessage = "Could not send verification code. Please try again."
        }

        isLoading = false
    }

    func verifyPhoneOTP() async {
        guard otpCode.count == 6 else {
            errorMessage = "Please enter the 6-digit code"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            currentUser = try await AuthService.shared.verifyPhoneOTP(phone: phoneNumber, code: otpCode)
            authState = .authenticated
            clearFormFields()
        } catch {
            errorMessage = "Invalid code. Please try again."
            otpCode = ""
        }

        isLoading = false
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
            currentUser = nil
            authState = .unauthenticated
            clearFormFields()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    // MARK: - Helpers

    private func clearFormFields() {
        email = ""
        password = ""
        displayName = ""
        phoneNumber = ""
        otpCode = ""
        isAwaitingOTP = false
    }
}
