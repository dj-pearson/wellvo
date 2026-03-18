import SwiftUI
import AuthenticationServices
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

    /// Prepare the Apple Sign-In request with a cryptographic nonce.
    /// Call this from the SignInWithAppleButton's `onRequest` closure.
    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        Task {
            let rawNonce = await AuthService.shared.generateNonce()
            let hashedNonce = await AuthService.shared.sha256(rawNonce)
            await MainActor.run {
                self.currentRawNonce = rawNonce
            }
            await MainActor.run {
                request.requestedScopes = [.fullName, .email]
                request.nonce = hashedNonce
            }
        }
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
            do {
                currentUser = try await AuthService.shared.signInWithApple(credential: credential)
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
    }
}
