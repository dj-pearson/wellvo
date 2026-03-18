import Foundation

enum Configuration {
    // MARK: - Supabase

    static var supabaseURL: String {
        guard let value = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String, !value.isEmpty else {
            #if DEBUG
            return "http://localhost:8000"
            #else
            fatalError("SUPABASE_URL not configured in Info.plist")
            #endif
        }
        return value
    }

    static var supabaseAnonKey: String {
        guard let value = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !value.isEmpty else {
            #if DEBUG
            return "your-anon-key-here"
            #else
            fatalError("SUPABASE_ANON_KEY not configured in Info.plist")
            #endif
        }
        return value
    }

    // MARK: - App

    static let appScheme = "wellvo"
    static let appDomain = "wellvo.net"
}
