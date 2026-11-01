import Foundation
import Supabase
import os

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        let urlString = Configuration.supabaseURL
        let anonKey = Configuration.supabaseAnonKey

        guard !urlString.isEmpty, let supabaseURL = URL(string: urlString) else {
            preconditionFailure(
                "Invalid Supabase URL: '\(urlString)'. Ensure SUPABASE_URL is set in BuildConfig.xcconfig and Info.plist."
            )
        }

        guard !anonKey.isEmpty, anonKey != "your-anon-key-here" else {
            preconditionFailure(
                "Invalid Supabase anon key. Ensure SUPABASE_ANON_KEY is set in BuildConfig.xcconfig and Info.plist."
            )
        }

        // App-owned session storage rather than the SDK default (US-IOS144).
        // The default is `KeychainLocalStorage(service: "supabase.gotrue.swift")`,
        // whose items survive an app delete and sat outside the fresh-install
        // purge — so a reinstall could restore the previous owner's session.
        // See SupabaseSessionStorage for the migration that carries existing
        // users across without signing them out.
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: SupabaseSessionStorage()
                )
            )
        )

        // Share URLs with Notification Service Extension via App Group
        let sharedDefaults = UserDefaults(suiteName: "group.com.wellvo.ios")
        sharedDefaults?.set(urlString, forKey: "supabase_url")
        sharedDefaults?.set(Configuration.edgeFunctionsURL, forKey: "edge_functions_url")
        // The anon key too, so the Notification Service Extension can refresh an
        // expired access token before confirming delivery (US-IOS145). It is a
        // publishable key, not a secret: it already ships in the app binary and
        // already sits in this same App Group container inside the
        // SharedCheckInState snapshot. The session TOKENS stay in the encrypted
        // Keychain, which is the distinction SharedKeychain's doc comment draws.
        sharedDefaults?.set(anonKey, forKey: "supabase_anon_key")
    }

    /// Mirrors the current session into the shared Keychain so the Notification
    /// Service Extension and the widget / Siri / watch surfaces can confirm
    /// delivery and perform a check-in. Call after successful auth and on token
    /// refresh.
    func syncAccessTokenToExtension() async {
        // Adopt an extension-rotated session BEFORE `client.auth.session`, which
        // would otherwise refresh with the SDK's already-consumed refresh token
        // (and then overwrite the good shared pair with the dead one).
        await adoptNewerSharedSessionIfNeeded()
        guard let session = try? await client.auth.session else { return }
        // Migrate away from the two earlier storage locations: the plaintext
        // App Group UserDefaults key, and the non-access-group Keychain item
        // (which the extension could never read).
        let sharedDefaults = UserDefaults(suiteName: "group.com.wellvo.ios")
        sharedDefaults?.removeObject(forKey: "supabase_access_token")
        KeychainService.delete(key: "supabase_access_token")

        SharedKeychain.saveTokens(SharedAuthTokens(session: session))
    }

    /// Pull a refresh-token rotation made by an extension back into the SDK.
    ///
    /// The Notification Service Extension and `SharedCheckInClient` (widget,
    /// Control Center, Siri, watch hand-off) refresh an expired access token on
    /// their own and write the rotated pair to `SharedKeychain`. Supabase
    /// invalidates a refresh token on use, so from that moment the copy in the
    /// SDK's own session storage is dead — and nothing copied the new one back:
    /// `syncAccessTokenToExtension` only goes app -> shared. The app's next
    /// refresh presented the consumed token and the user was signed out.
    ///
    /// Call before any network call on launch and on foreground. Cheap when
    /// there is nothing to do (two Keychain reads); concurrent callers share one
    /// in-flight adoption so the rotated refresh token is never spent twice.
    func adoptNewerSharedSessionIfNeeded() async {
        await SharedSessionReconciler.shared.adoptNewerSharedSessionIfNeeded()
    }
}

extension SharedAuthTokens {
    /// The mirrored form of an SDK session, stamped with its issue time
    /// (`expiresAt - expiresIn`, both server-reported) so the reconciler can
    /// compare it against an extension-rotated pair.
    init(session: Session) {
        self.init(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            issuedAt: Date(timeIntervalSince1970: session.expiresAt - session.expiresIn)
        )
    }
}

/// Serializes `SupabaseService.adoptNewerSharedSessionIfNeeded`. Launch fires
/// it from both `AuthViewModel.checkSession` and the AppDelegate's
/// `syncAccessTokenToExtension`; without coalescing, two `setSession` calls
/// with an expired shared access token would each refresh with the same
/// refresh token and the second would fail.
actor SharedSessionReconciler {
    static let shared = SharedSessionReconciler()

    private var inFlight: Task<Void, Never>?

    func adoptNewerSharedSessionIfNeeded() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await Self.reconcile() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private static func reconcile() async {
        let auth = SupabaseService.shared.client.auth
        // `currentSession` reads storage without validating or refreshing —
        // `auth.session` would refresh with the very token we suspect is dead.
        guard let shared = SharedKeychain.loadTokens(),
              let sdk = auth.currentSession else { return }

        guard shouldAdopt(
            shared: shared,
            sdkRefreshToken: sdk.refreshToken,
            sdkExpiresAt: Date(timeIntervalSince1970: sdk.expiresAt),
            sdkIssuedAt: Date(timeIntervalSince1970: sdk.expiresAt - sdk.expiresIn),
            sdkUserId: sdk.user.id
        ) else { return }

        do {
            // Validates the pair (fetches the user, or refreshes if the shared
            // access token has itself expired) and stores it as the SDK session.
            _ = try await auth.setSession(
                accessToken: shared.accessToken,
                refreshToken: shared.refreshToken
            )
            Log.auth.info("Adopted extension-rotated session from shared Keychain")
        } catch {
            // Leave the SDK session as it was. Offline this simply retries on
            // the next foreground; a server rejection means the shared pair was
            // not usable either, and the normal session check decides.
            Log.auth.error("Adopting shared session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether the mirrored pair is a strictly newer session for the same user
    /// than the SDK's own. Every condition must hold — adopting an OLDER pair
    /// would install a refresh token that has already been spent, which is the
    /// sign-out this exists to prevent, so any doubt keeps the SDK session.
    ///
    /// - Different refresh token (equal means already in sync).
    /// - Same user, read from the shared access token's `sub` claim — a stale
    ///   pair from a previous account must never replace the current one.
    /// - Later access-token expiry. Works for pairs written before `issuedAt`
    ///   existed.
    /// - When stamped, issued after the SDK session. Guards the race where a
    ///   mirror read session X, the SDK then rotated to Y, and the late write of
    ///   X would otherwise look fresh.
    nonisolated static func shouldAdopt(
        shared: SharedAuthTokens,
        sdkRefreshToken: String,
        sdkExpiresAt: Date,
        sdkIssuedAt: Date,
        sdkUserId: UUID
    ) -> Bool {
        guard !shared.refreshToken.isEmpty,
              !shared.accessToken.isEmpty,
              shared.refreshToken != sdkRefreshToken else { return false }
        guard let subject = jwtSubject(shared.accessToken),
              let subjectId = UUID(uuidString: subject),
              subjectId == sdkUserId else { return false }
        guard shared.expiresAt > sdkExpiresAt else { return false }
        if let issuedAt = shared.issuedAt, issuedAt <= sdkIssuedAt { return false }
        return true
    }

    /// The `sub` claim of a JWT, without verifying it — used only to match the
    /// shared pair to the signed-in user; `setSession` validates it with the
    /// server.
    nonisolated static func jwtSubject(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return claims["sub"] as? String
    }
}
