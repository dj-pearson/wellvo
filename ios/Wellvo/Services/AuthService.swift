import Foundation
import Supabase
import AuthenticationServices

actor AuthService {
    static let shared = AuthService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> AppUser {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: tokenString)
        )

        // Update user profile with Apple-provided info if available
        var displayName = "User"
        if let fullName = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: fullName)
            if !name.isEmpty { displayName = name }
        }

        let user: AppUser = try await supabase
            .from("users")
            .upsert([
                "id": session.user.id.uuidString,
                "email": credential.email ?? session.user.email ?? "",
                "display_name": displayName,
                "timezone": TimeZone.current.identifier,
            ])
            .select()
            .single()
            .execute()
            .value

        return user
    }

    func signInWithEmail(email: String, password: String) async throws -> AppUser {
        let session = try await supabase.auth.signIn(email: email, password: password)

        let user: AppUser = try await supabase
            .from("users")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        return user
    }

    func signUpWithEmail(email: String, password: String, displayName: String) async throws -> AppUser {
        let session = try await supabase.auth.signUp(email: email, password: password)

        let user: AppUser = try await supabase
            .from("users")
            .insert([
                "id": session.user.id.uuidString,
                "email": email,
                "display_name": displayName,
                "timezone": TimeZone.current.identifier,
            ])
            .select()
            .single()
            .execute()
            .value

        return user
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    func currentSession() async throws -> AppUser? {
        guard let session = try? await supabase.auth.session else { return nil }

        let user: AppUser = try await supabase
            .from("users")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        return user
    }
}

enum AuthError: LocalizedError {
    case invalidCredential
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Invalid sign-in credential"
        case .userNotFound: return "User not found"
        }
    }
}
