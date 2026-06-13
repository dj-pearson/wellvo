import Foundation

/// Decides *when* to ask for an App Store rating. The actual system prompt is
/// presented by the views via SwiftUI's `requestReview` environment action;
/// this service owns only the eligibility logic so it stays pure and testable.
///
/// Apple hard-caps the system prompt to 3 per 365 days and may silently drop
/// requests, so we add stricter gating and only ever ask at a genuinely
/// positive moment:
///   • Receiver — after their `checkInThreshold`-th confirmed check-in.
///   • Owner    — when a receiver reaches an `ownerStreakThreshold`-day streak.
/// We never ask twice on the same app version, nor within `minDaysBetweenPrompts`
/// days of a previous ask.
///
/// All state is local (UserDefaults) — no schema, API, or on-device-migration
/// impact. The thresholds, clock, version, and store are injectable for tests.
@MainActor
final class ReviewPromptService {
    static let shared = ReviewPromptService()

    private let checkInThreshold: Int
    private let ownerStreakThreshold: Int
    private let minDaysBetweenPrompts: Int

    private let defaults: UserDefaults
    private let appVersion: String
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        appVersion: String = ReviewPromptService.bundleShortVersion(),
        now: @escaping () -> Date = Date.init,
        checkInThreshold: Int = 5,
        ownerStreakThreshold: Int = 7,
        minDaysBetweenPrompts: Int = 120
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.now = now
        self.checkInThreshold = checkInThreshold
        self.ownerStreakThreshold = ownerStreakThreshold
        self.minDaysBetweenPrompts = minDaysBetweenPrompts
    }

    private enum Key {
        static let checkInCount = "reviewPrompt.successfulCheckInCount"
        static let lastPromptedDate = "reviewPrompt.lastPromptedDate"
        static let lastPromptedVersion = "reviewPrompt.lastPromptedVersion"
    }

    // MARK: - Triggers

    /// Record a confirmed (server-persisted) receiver check-in. Returns `true`
    /// when this check-in makes the user eligible to be asked right now.
    @discardableResult
    func registerSuccessfulCheckIn() -> Bool {
        let count = defaults.integer(forKey: Key.checkInCount) + 1
        defaults.set(count, forKey: Key.checkInCount)
        guard count >= checkInThreshold else { return false }
        return isEligibleToPrompt()
    }

    /// Whether the owner should be asked now, given the best current receiver
    /// streak across their family.
    func shouldPromptForOwnerStreak(maxStreak: Int) -> Bool {
        guard maxStreak >= ownerStreakThreshold else { return false }
        return isEligibleToPrompt()
    }

    /// Shared throttle: never twice on the same app version, and never within
    /// `minDaysBetweenPrompts` days of the last ask.
    func isEligibleToPrompt() -> Bool {
        if defaults.string(forKey: Key.lastPromptedVersion) == appVersion {
            return false
        }
        if let last = defaults.object(forKey: Key.lastPromptedDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: now()).day ?? Int.max
            if days < minDaysBetweenPrompts { return false }
        }
        return true
    }

    /// Record that the system prompt was just requested. Call immediately after
    /// invoking the SwiftUI `requestReview` action so we don't ask again this
    /// version / throttle window.
    func markPrompted() {
        defaults.set(now(), forKey: Key.lastPromptedDate)
        defaults.set(appVersion, forKey: Key.lastPromptedVersion)
    }

    // MARK: - Helpers

    nonisolated static func bundleShortVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }
}
