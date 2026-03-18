import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        guard let supabaseURL = URL(string: Configuration.supabaseURL) else {
            fatalError("Invalid Supabase URL in configuration")
        }
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: Configuration.supabaseAnonKey
        )
    }
}
