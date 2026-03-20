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

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey
        )

        // Share Supabase URL with Notification Service Extension via App Group
        let sharedDefaults = UserDefaults(suiteName: "group.com.wellvo.ios")
        sharedDefaults?.set(urlString, forKey: "supabase_url")
    }

    /// Writes the current access token to shared App Group storage
    /// so the Notification Service Extension can confirm delivery.
    /// Call this after successful auth and on token refresh.
    func syncAccessTokenToExtension() async {
        guard let session = try? await client.auth.session else { return }
        let sharedDefaults = UserDefaults(suiteName: "group.com.wellvo.ios")
        sharedDefaults?.set(session.accessToken, forKey: "supabase_access_token")
    }
}
