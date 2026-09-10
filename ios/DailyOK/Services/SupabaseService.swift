import Foundation
import Supabase

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
        guard let session = try? await client.auth.session else { return }
        // Migrate away from the two earlier storage locations: the plaintext
        // App Group UserDefaults key, and the non-access-group Keychain item
        // (which the extension could never read).
        let sharedDefaults = UserDefaults(suiteName: "group.com.wellvo.ios")
        sharedDefaults?.removeObject(forKey: "supabase_access_token")
        KeychainService.delete(key: "supabase_access_token")

        SharedKeychain.saveTokens(SharedAuthTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        ))
    }
}
