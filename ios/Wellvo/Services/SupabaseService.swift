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
    }
}
