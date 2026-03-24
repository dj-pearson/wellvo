import Foundation
import Security
import Supabase
import AuthenticationServices
import CryptoKit

actor AuthService {
    static let shared = AuthService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    /// Stored nonce for the current Apple Sign-In flow (SHA256-hashed version sent to Apple)
    private var currentNonce: String?

    // MARK: - Apple Sign-In

    /// Generate a cryptographic nonce for Apple Sign-In (prevents replay attacks).
    /// Call this before presenting the Apple Sign-In sheet, and pass the raw nonce
    /// into the ASAuthorizationAppleIDRequest.
    func generateNonce() -> String {
        let nonce = randomNonceString(length: 32)
        currentNonce = nonce
        return nonce
    }

    /// Returns the SHA256 hash of a nonce string (Apple requires the hashed version).
    func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws -> AppUser {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: tokenString,
                nonce: rawNonce
            )
        )

        // Apple only provides name and email on the FIRST sign-in.
        // On subsequent sign-ins, these fields are nil.
        // We must only update displayName if Apple actually provided it.
        let appleProvidedName: String? = {
            guard let fullName = credential.fullName else { return nil }
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: fullName)
            return name.isEmpty ? nil : name
        }()

        let appleProvidedEmail = credential.email

        // First, check if user profile already exists
        let existingUser: AppUser? = try? await supabase
            .from("users")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        if let existing = existingUser {
            // Only update fields that Apple actually provided (non-nil)
            var updates: [String: String] = [
                "timezone": TimeZone.current.identifier,
            ]
            if let name = appleProvidedName {
                updates["display_name"] = name
            }
            if let email = appleProvidedEmail {
                updates["email"] = email
            }

            let user: AppUser = try await supabase
                .from("users")
                .update(updates)
                .eq("id", value: existing.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            // Persist the Apple user ID for revocation checks
            persistAppleUserID(credential.user)

            return user
        } else {
            // First-time sign-in — create user profile
            let user: AppUser = try await supabase
                .from("users")
                .insert([
                    "id": session.user.id.uuidString,
                    "email": appleProvidedEmail ?? session.user.email ?? "",
                    "display_name": appleProvidedName ?? "User",
                    "timezone": TimeZone.current.identifier,
                ])
                .select()
                .single()
                .execute()
                .value

            persistAppleUserID(credential.user)

            return user
        }
    }

    // MARK: - Email Auth

    func signInWithEmail(email: String, password: String) async throws -> AppUser {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try validateEmail(trimmedEmail)

        let session = try await supabase.auth.signIn(email: trimmedEmail, password: password)

        return try await findOrCreateUserProfile(
            userId: session.user.id,
            email: trimmedEmail,
            displayName: nil
        )
    }

    func signUpWithEmail(email: String, password: String, displayName: String) async throws -> AppUser {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        try validateEmail(trimmedEmail)
        try validatePassword(password)

        guard !trimmedName.isEmpty else {
            throw AuthError.invalidDisplayName
        }

        let session = try await supabase.auth.signUp(email: trimmedEmail, password: password)

        return try await findOrCreateUserProfile(
            userId: session.user.id,
            email: trimmedEmail,
            displayName: trimmedName
        )
    }

    /// Fetch existing user profile, or create one if it doesn't exist yet.
    private func findOrCreateUserProfile(userId: UUID, email: String?, displayName: String?, phone: String? = nil) async throws -> AppUser {
        // Try to find existing profile
        let existing: AppUser? = try? await supabase
            .from("users")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value

        if let existing { return existing }

        // Profile doesn't exist — create it
        var fields: [String: String] = [
            "id": userId.uuidString,
            "email": email ?? "",
            "display_name": displayName ?? "User",
            "timezone": TimeZone.current.identifier,
        ]
        if let phone {
            fields["phone"] = phone
        }

        let user: AppUser = try await supabase
            .from("users")
            .upsert(fields)
            .select()
            .single()
            .execute()
            .value

        return user
    }

    // MARK: - Phone OTP Auth

    /// Send a one-time passcode to the given phone number via SMS.
    func sendPhoneOTP(phone: String) async throws {
        let normalized = normalizePhone(phone)
        try await supabase.auth.signInWithOTP(phone: normalized)
    }

    /// Verify the OTP code and sign the user in.
    func verifyPhoneOTP(phone: String, code: String) async throws -> AppUser {
        let normalized = normalizePhone(phone)
        let session = try await supabase.auth.verifyOTP(
            phone: normalized,
            token: code,
            type: .sms
        )

        return try await findOrCreateUserProfile(
            userId: session.user.id,
            email: nil,
            displayName: nil,
            phone: normalized
        )
    }

    /// Normalize a US phone number to +1XXXXXXXXXX format.
    private func normalizePhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if digits.count == 10 {
            return "+1\(digits)"
        } else if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }
        return phone.hasPrefix("+") ? phone : "+\(digits)"
    }

    // MARK: - Session Management

    func signOut() async throws {
        clearAppleUserID()
        try await supabase.auth.signOut()
    }

    func currentSession() async throws -> AppUser? {
        guard let session = try? await supabase.auth.session else { return nil }

        let user: AppUser? = try? await supabase
            .from("users")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        return user
    }

    /// Check if the Apple credential is still valid (not revoked).
    /// Should be called on app launch and periodically.
    func checkAppleCredentialStatus() async -> Bool {
        guard let appleUserID = getPersistedAppleUserID() else { return true }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: appleUserID)
            return state == .authorized
        } catch {
            return true // Don't sign out on transient errors
        }
    }

    // MARK: - Validation

    private func validateEmail(_ email: String) throws {
        let emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        guard email.wholeMatch(of: emailRegex) != nil else {
            throw AuthError.invalidEmail
        }
    }

    private func validatePassword(_ password: String) throws {
        guard password.count >= 8 else {
            throw AuthError.passwordTooShort
        }
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        guard hasUppercase && hasLowercase && hasNumber else {
            throw AuthError.passwordTooWeak
        }
    }

    // MARK: - Apple User ID Persistence (Keychain)

    private let appleUserIDKey = "appleUserID"

    private func persistAppleUserID(_ userID: String) {
        _ = KeychainService.save(key: appleUserIDKey, value: userID)
    }

    private func getPersistedAppleUserID() -> String? {
        KeychainService.load(key: appleUserIDKey)
    }

    private func clearAppleUserID() {
        KeychainService.delete(key: appleUserIDKey)
    }

    // MARK: - Nonce Generation

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else {
            // Fallback to UUID-based nonce
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case missingNonce
    case userNotFound
    case invalidEmail
    case passwordTooShort
    case passwordTooWeak
    case invalidDisplayName
    case credentialRevoked

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Invalid sign-in credential."
        case .missingNonce: return "Sign-in security check failed. Please try again."
        case .userNotFound: return "User not found."
        case .invalidEmail: return "Please enter a valid email address."
        case .passwordTooShort: return "Password must be at least 8 characters."
        case .passwordTooWeak: return "Password must contain uppercase, lowercase, and a number."
        case .invalidDisplayName: return "Please enter your name."
        case .credentialRevoked: return "Your Apple ID access has been revoked. Please sign in again."
        }
    }
}
