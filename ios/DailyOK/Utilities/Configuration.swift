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
            // Fail fast instead of shipping an app with an empty base URL that
            // silently can't reach the backend — every auth/check-in would fail
            // against "". A missing key here means the CI plist injection broke;
            // this crash is caught in TestFlight smoke, not by real users
            // (US-IOS093). CI also hard-fails on an empty injected value.
            fatalError("Missing SUPABASE_URL — Info.plist config was not injected at build time.")
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
            // See supabaseURL — fail fast rather than ship a backend-less app.
            fatalError("Missing SUPABASE_ANON_KEY — Info.plist config was not injected at build time.")
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

    /// Marketing version (CFBundleShortVersionString), e.g. "1.4.0". Sent to the
    /// backend so it can enforce MIN_SUPPORTED_IOS_APP_VERSION (force-update).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fallback App Store URL used by the force-update screen if the server
    /// didn't supply one.
    static let appStoreURL = "https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697"
}
