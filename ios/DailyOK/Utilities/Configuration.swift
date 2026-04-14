import Foundation

enum Configuration {
    // MARK: - Supabase

    static var supabaseURL: String {
        guard let value = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              !value.isEmpty,
              value != "$(SUPABASE_URL)",
              !value.hasPrefix("REPLACE_AT_BUILD") else {
            #if DEBUG
            return "http://localhost:8000"
            #else
            return ""
            #endif
        }
        return value
    }

    /// Base URL for the self-hosted edge-functions Deno server (Coolify container).
    /// Function calls are POSTed to `<edgeFunctionsURL>/<function-name>`.
    static var edgeFunctionsURL: String {
        guard let value = Bundle.main.infoDictionary?["EDGE_FUNCTIONS_URL"] as? String,
              !value.isEmpty,
              value != "$(EDGE_FUNCTIONS_URL)",
              !value.hasPrefix("REPLACE_AT_BUILD") else {
            #if DEBUG
            return "http://localhost:9000"
            #else
            return "https://functions.dailyok.net"
            #endif
        }
        return value
    }

    static var supabaseAnonKey: String {
        guard let value = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
              !value.isEmpty,
              value != "$(SUPABASE_ANON_KEY)",
              !value.hasPrefix("REPLACE_AT_BUILD") else {
            #if DEBUG
            return "your-anon-key-here"
            #else
            return ""
            #endif
        }
        return value
    }

    // MARK: - Analytics

    static var telemetryAppID: String {
        guard let value = Bundle.main.infoDictionary?["TELEMETRY_APP_ID"] as? String, !value.isEmpty else {
            #if DEBUG
            return ""
            #else
            return ""
            #endif
        }
        return value
    }

    // MARK: - App

    static let appScheme = "dailyok"
    static let appDomain = "dailyok.net"
}
