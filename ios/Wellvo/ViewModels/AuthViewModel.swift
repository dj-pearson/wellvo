import SwiftUI
import AuthenticationServices

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

    init() {
        Task { await checkSession() }
    }

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
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

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
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
            currentUser = nil
            authState = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
