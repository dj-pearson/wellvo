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
    func generateNonce() throws -> String {
        guard let nonce = randomNonceString(length: 32) else {
            throw AuthError.missingNonce
        }
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
        let existingUser: AppUser? = try? await fetchMyProfile(userId: session.user.id)

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

            // `returning: .minimal`: a returned row is `select=*`, which names
            // email and phone, and the staged column revoke hides those from
            // direct reads (your own row too). Read it back through
            // get_my_profile instead.
            try await supabase
                .from("users")
                .update(updates, returning: .minimal)
                .eq("id", value: existing.id.uuidString)
                .execute()
            guard let user = try await fetchMyProfile(userId: existing.id) else {
                throw AuthError.userNotFound
            }

            // Persist the Apple user ID for revocation checks
            persistAppleUserID(credential.user)

            return user
        } else {
            // First-time sign-in — create user profile
            try await supabase
                .from("users")
                .insert([
                    "id": session.user.id.uuidString,
                    "email": appleProvidedEmail ?? session.user.email ?? "",
                    "display_name": appleProvidedName ?? "User",
                    "timezone": TimeZone.current.identifier,
                ])
                .execute()
            guard let user = try await fetchMyProfile(userId: session.user.id) else {
                throw AuthError.userNotFound
            }

            persistAppleUserID(credential.user)

            return user
        }
    }

    // MARK: - Link Apple ID

    /// Link an Apple identity to the currently signed-in user.
    /// This allows users who signed up with email (or, before it was retired, a phone number) to later use "Sign in with Apple."
    func linkAppleID(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        guard let session = try? await supabase.auth.session else {
            throw AuthError.userNotFound
        }

        // Send the Apple identity token to our edge function which verifies it
        // and links the identity in auth.identities via the admin API.
        let hashedNonce = sha256(rawNonce)
        try await EdgeFunctionsClient.invoke(
            "link-apple-id",
            body: [
                "identity_token": tokenString,
                "nonce": hashedNonce,
                // Lets the server check that this device started the sign-in
                // (a captured identity token alone can't be replayed). Older
                // servers ignore it.
                "raw_nonce": rawNonce,
            ]
        )

        // Persist the Apple user ID for revocation checks
        persistAppleUserID(credential.user)
    }

    /// Push the device's current IANA timezone to `users.timezone` when it
    /// differs from the stored value. The edge-function dedup and the owner
    /// dashboard's "today" window both key off this column, so a stale value
    /// (user traveled, new device, wrong region on first signup) produces
    /// off-by-hours bugs. Best-effort: silent no-op on any failure.
    func syncTimezoneIfChanged() async {
        guard let session = try? await supabase.auth.session else { return }
        let deviceTz = TimeZone.current.identifier
        guard !deviceTz.isEmpty else { return }

        struct TimezoneOnly: Decodable { let timezone: String? }
        let stored: TimezoneOnly? = try? await supabase
            .from("users")
            .select("timezone")
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        guard stored?.timezone != deviceTz else { return }

        _ = try? await supabase
            .from("users")
            .update(["timezone": deviceTz], returning: .minimal)
            .eq("id", value: session.user.id.uuidString)
            .execute()
    }

    /// Check if the current user has an Apple identity linked.
    func hasLinkedAppleID() async -> Bool {
        (await appleIDLinkStatus()) ?? false
    }

    /// Like `hasLinkedAppleID`, but `nil` when it couldn't be checked (offline,
    /// server error), so Settings doesn't offer to link an Apple ID that is
    /// already linked just because the check failed.
    func appleIDLinkStatus() async -> Bool? {
        guard let session = try? await supabase.auth.session else { return nil }
        // Self-only check (00060). has_apple_identity(p_user_id) answers for
        // any user id, so it is kept only as the fallback for a backend that
        // predates the new function.
        if let mine: Bool = try? await supabase
            .rpc("has_my_apple_identity")
            .execute()
            .value {
            return mine
        }
        return try? await supabase
            .rpc("has_apple_identity", params: ["p_user_id": session.user.id.uuidString])
            .execute()
            .value
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
    private func findOrCreateUserProfile(userId: UUID, email: String?, displayName: String?) async throws -> AppUser {
        // Distinguish "profile doesn't exist" (empty result) from "the lookup
        // failed" (network blip / RLS / timeout). The old `try?` + `.single()`
        // collapsed BOTH to nil, which then fell through to the upsert below and
        // — because the row already existed — OVERWROTE the real display_name
        // with "User" and re-set the email. Fetch as an array with a limit so a
        // genuine not-found is an empty array, while a transient error THROWS and
        // propagates instead of clobbering the profile.
        if let existing = try await fetchMyProfile(userId: userId) { return existing }

        // Profile doesn't exist — create it
        let fields: [String: String] = [
            "id": userId.uuidString,
            "email": email ?? "",
            "display_name": displayName ?? "User",
            "timezone": TimeZone.current.identifier,
        ]

        // ignoreDuplicates (ON CONFLICT DO NOTHING): a row that appeared
        // meanwhile (the auth.users trigger) is kept as it is, never
        // overwritten. A DO UPDATE would also need SELECT on email, which the
        // staged column revoke takes away.
        try await supabase
            .from("users")
            .upsert(fields, returning: .minimal, ignoreDuplicates: true)
            .execute()
        guard let user = try await fetchMyProfile(userId: userId) else {
            throw AuthError.userNotFound
        }
        return user
    }

    /// The signed-in user's own profile, every column, or nil when there is no
    /// profile row yet. Throws when the lookup fails.
    ///
    /// Reads through `get_my_profile()` (00067), not the table: a staged
    /// migration revokes column SELECT on users.email / phone /
    /// is_system_admin, and column privileges bind your own row too. A server
    /// without the function yet gets the same columns from the table.
    private func fetchMyProfile(userId: UUID) async throws -> AppUser? {
        do {
            let rows: [AppUser] = try await supabase
                .rpc("get_my_profile")
                .execute()
                .value
            return rows.first
        } catch let error where FamilyService.isMissingFunction(error) {
            let rows: [AppUser] = try await supabase
                .from("users")
                .select(AppUser.selfColumns)
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        }
    }

    // MARK: - Accounts without an email (phone sign-in was retired)

    /// True when the signed-in account has no email address: it was created
    /// with phone-number sign-in, which the app no longer offers (server-sent
    /// SMS codes would need A2P 10DLC registration). Such a user can keep using
    /// the session they have, but once signed out there is no way back in, so
    /// the app asks them to add an email while it still can.
    func signedInAccountLacksEmail() async -> Bool {
        guard let user = try? await supabase.auth.session.user else { return false }
        return Self.accountLacksEmail(email: user.email)
    }

    /// Pure core of `signedInAccountLacksEmail`. An address still waiting for
    /// confirmation lives in `new_email`, not `email`, so it counts as missing:
    /// until it is confirmed it cannot be used to sign in.
    nonisolated static func accountLacksEmail(email: String?) -> Bool {
        (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ask GoTrue to attach `email` to the signed-in account. It emails a
    /// 6-digit code (and a link) to that address; nothing changes until the
    /// code is confirmed with `confirmAddedEmail`.
    func requestAddEmail(_ email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try validateEmail(trimmed)
        _ = try await supabase.auth.update(user: UserAttributes(email: trimmed))
    }

    /// Confirm the code from the add-email message. On success the address is
    /// the account's sign-in email; the profile row is updated to match
    /// (best-effort: auth.users is what sign-in reads).
    func confirmAddedEmail(_ email: String, code: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try validateEmail(trimmed)
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { throw AuthError.invalidRecoveryCode }

        _ = try await supabase.auth.verifyOTP(
            email: trimmed,
            token: digits,
            type: .emailChange
        )
        await syncProfileEmail()
    }

    /// Whether the account now has a confirmed email, after the user tapped
    /// the link in the message instead of typing the code. Refreshes the
    /// session so the answer comes from the server, not a cached user.
    func refreshAddedEmailStatus() async -> Bool {
        guard let session = try? await supabase.auth.refreshSession() else { return false }
        let hasEmail = !Self.accountLacksEmail(email: session.user.email)
        if hasEmail { await syncProfileEmail() }
        return hasEmail
    }

    /// Copy the confirmed auth email onto users.email (client-writable column).
    private func syncProfileEmail() async {
        guard let user = try? await supabase.auth.session.user,
              let email = user.email, !email.isEmpty else { return }
        _ = try? await supabase
            .from("users")
            .update(["email": email], returning: .minimal)
            .eq("id", value: user.id.uuidString)
            .execute()
    }

    // MARK: - Password Reset

    /// Send a password reset email. Does not reveal whether the email exists.
    ///
    /// The reset email carries BOTH a link and a 6-digit code. This app uses the
    /// CODE (see verifyRecoveryCode below) and deliberately passes no redirectTo:
    /// dailyok.net serves marketing pages and has no auth callback route, so the
    /// link has nowhere useful to land whatever we point it at.
    func resetPassword(email: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try validateEmail(trimmedEmail)
        try await supabase.auth.resetPasswordForEmail(trimmedEmail)
    }

    /// Verify the 6-digit recovery code from the reset email, which establishes a
    /// session just long enough to set a new password.
    ///
    /// GoTrue's default recovery template emits "Alternatively, enter the code:
    /// {{ .Token }}" alongside the link, so the code is already in every reset
    /// email that has ever been sent. Unlike the link it needs no redirect, no
    /// allow-list entry and no web page, which is why it is the path a native app
    /// should take.
    func verifyRecoveryCode(email: String, code: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try validateEmail(trimmedEmail)

        // Strip formatting the user may have pasted in from the email body.
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { throw AuthError.invalidRecoveryCode }

        _ = try await supabase.auth.verifyOTP(
            email: trimmedEmail,
            token: digits,
            type: .recovery
        )
    }

    /// Set a new password on the session established by verifyRecoveryCode.
    ///
    /// Validated with the same rules as signup: a reset is the one moment a weak
    /// password could otherwise slip past the signup checks entirely.
    func updatePassword(_ newPassword: String) async throws {
        try validatePassword(newPassword)
        _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    // MARK: - Session Management

    func signOut() async throws {
        clearAppleUserID()
        try await supabase.auth.signOut()
    }

    /// Resolve the signed-in user's profile.
    ///
    /// Returns `nil` ONLY when there is no auth session (genuinely signed out).
    /// When a session IS present but the profile fetch fails transiently, this
    /// THROWS rather than returning nil — the previous `try?` -> nil made a
    /// network blip on foreground indistinguishable from a signed-out state and
    /// bounced a logged-in user to the sign-in screen. Callers must not treat a
    /// thrown error here as "signed out" (see `AuthViewModel.checkSession`).
    ///
    /// "No session" means nothing is stored, or the server REFUSED the stored
    /// one (revoked / expired refresh token). A refresh that failed because the
    /// device is offline is not that: access tokens last about an hour and a
    /// receiver opens the app once a day, so `try?` on `auth.session` (which
    /// refreshes an expired token over the network) turned every offline
    /// launch into the sign-in screen, and the offline check-in queue could
    /// not be reached. That case now throws, like a failed profile fetch.
    func currentSession() async throws -> AppUser? {
        guard supabase.auth.currentSession != nil else { return nil }

        let userId: UUID
        do {
            userId = try await supabase.auth.session.user.id
        } catch {
            if Self.isConnectivityError(error) { throw error }
            return nil
        }

        // A missing profile throws, as `.single()` did before.
        guard let user = try await fetchMyProfile(userId: userId) else {
            throw AuthError.userNotFound
        }
        return user
    }

    /// A session is stored on this device (it may need a refresh). Does not
    /// touch the network.
    nonisolated var hasStoredSession: Bool {
        SupabaseService.shared.client.auth.currentSession != nil
    }

    /// The signed-in user's id from the stored session, without refreshing it,
    /// so an offline launch can still find its cached role.
    nonisolated var storedUserId: UUID? {
        SupabaseService.shared.client.auth.currentSession?.user.id
    }

    /// The request never got an answer from the server (offline, timed out,
    /// DNS, TLS). Distinct from the server saying no.
    nonisolated static func isConnectivityError(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let dailyOK = error as? DailyOKError {
            switch dailyOK {
            case .offline: return true
            case .network(let inner): return isConnectivityError(inner)
            default: return false
            }
        }
        return (error as NSError).domain == NSURLErrorDomain
    }

    /// Check if the Apple credential is still valid (not revoked). Returns true
    /// (stay signed in) for accounts that didn't use Sign in with Apple, and is
    /// deliberately conservative: only a *genuine* `.revoked` state signs the
    /// user out. `.notFound`/`.transferred` are ambiguous (and `.notFound` can
    /// occur transiently), and a thrown error is treated as transient — none of
    /// those should nuke an otherwise-valid Supabase session.
    /// Should be called on app launch and periodically.
    func checkAppleCredentialStatus() async -> Bool {
        // Only meaningful for accounts linked to an Apple identity.
        guard let appleUserID = getPersistedAppleUserID() else { return true }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: appleUserID)
            return state != .revoked
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

    private static let commonPasswords: Set<String> = [
        "password", "123456789", "1234567890", "qwerty1234", "iloveyou1",
        "password1", "password12", "password123", "letmein123", "welcome123",
        "monkey1234", "dragon1234", "master1234", "qwertyuiop", "1234567891",
        "trustno1A", "sunshine12", "princess12", "football12", "charlie123",
        "shadow1234", "michael123", "jennifer12", "hunter1234", "thomas1234",
        "jordan1234", "mustang123", "access1234", "123456789a", "abcdefghij",
    ]

    private func validatePassword(_ password: String) throws {
        guard password.count >= 10 else {
            throw AuthError.passwordTooShort
        }
        guard password.count <= 128 else {
            throw AuthError.passwordTooWeak
        }
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        guard hasUppercase && hasLowercase && hasNumber else {
            throw AuthError.passwordTooWeak
        }
        guard !Self.commonPasswords.contains(password.lowercased()) else {
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

    /// Cryptographically-random nonce, or `nil` if the system CSPRNG fails.
    /// Never falls back to a non-cryptographic value (e.g. `UUID()`), which would
    /// undermine Apple Sign-In's replay protection. Callers must treat `nil` as a
    /// failed attempt and retry.
    private func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else { return nil }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
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
    case invalidRecoveryCode

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Invalid sign-in credential."
        case .missingNonce: return "Sign-in security check failed. Please try again."
        case .userNotFound: return "User not found."
        case .invalidEmail: return "Please enter a valid email address."
        case .passwordTooShort: return "Password must be at least 10 characters."
        case .passwordTooWeak: return "Password must contain uppercase, lowercase, and a number. Avoid common passwords."
        case .invalidDisplayName: return "Please enter your name."
        case .credentialRevoked: return "Your Apple ID access has been revoked. Please sign in again."
        case .invalidRecoveryCode: return "Enter the 6-digit code from your reset email."
        }
    }
}
