import Foundation
import os

/// Centralized, privacy-aware logging built on `os.Logger`.
///
/// Use these category loggers instead of `print(...)` / `NSLog(...)`. Unified
/// logging is structured, low-overhead, and — crucially — lets us mark
/// interpolated values as `.private` so user identifiers, timestamps, and other
/// PII are redacted in release builds (they show as `<private>` in Console.app /
/// sysdiagnose) while still being visible when debugging a connected device.
///
/// Guidance:
/// - Identifiers (user/family/receiver UUIDs), timestamps, emails, tokens, and
///   anything user-specific MUST be interpolated with `privacy: .private`.
/// - Only non-sensitive diagnostics (counts, states, fixed strings) should be
///   `.public`.
enum Log {
    // Match the app's real bundle identifier so logs filter by it (US-IOS108) —
    // the brand display name is "Daily OK" but the bundle id is com.wellvo.ios.
    private static let subsystem = "com.wellvo.ios"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let checkIn = Logger(subsystem: subsystem, category: "checkin")
    static let offline = Logger(subsystem: subsystem, category: "offline")
    static let push = Logger(subsystem: subsystem, category: "push")
    static let subscription = Logger(subsystem: subsystem, category: "subscription")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let receiver = Logger(subsystem: subsystem, category: "receiver")
    static let general = Logger(subsystem: subsystem, category: "general")
}
