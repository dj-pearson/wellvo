import Foundation

/// Pure functions for computing check-in streaks and consistency badges
/// from a list of ISO-8601 timestamps. Client-side only — no schema change.
enum Streaks {

    /// Current streak = consecutive calendar days up to today (or yesterday
    /// if today has no check-in yet) with at least one check-in.
    static func currentStreak(
        isoTimestamps: [String],
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> Int {
        guard !isoTimestamps.isEmpty else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let days: Set<Date> = Set(isoTimestamps.compactMap { iso in
            let date = formatter.date(from: iso) ?? fallbackFormatter.date(from: iso)
            return date.map { calendar.startOfDay(for: $0) }
        })
        guard !days.isEmpty else { return 0 }

        let startOfToday = calendar.startOfDay(for: today)
        var cursor = days.contains(startOfToday)
            ? startOfToday
            : calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Consistency percent for the last `windowDays` days (default 7), in 0..100.
    static func consistencyPercent(
        isoTimestamps: [String],
        windowDays: Int = 7,
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> Int {
        guard windowDays > 0 else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let startOfToday = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: startOfToday) else {
            return 0
        }

        let days: Set<Date> = Set(isoTimestamps.compactMap { iso -> Date? in
            let date = formatter.date(from: iso) ?? fallbackFormatter.date(from: iso)
            guard let date else { return nil }
            let day = calendar.startOfDay(for: date)
            guard day >= windowStart && day <= startOfToday else { return nil }
            return day
        })

        let pct = Double(days.count) / Double(windowDays) * 100
        return max(0, min(100, Int(pct)))
    }

    static func badge(consistencyPercent pct: Int) -> ConsistencyBadge {
        switch pct {
        case 100...:       return .gold
        case 80..<100:     return .silver
        case 50..<80:      return .bronze
        default:           return .none
        }
    }
}

enum ConsistencyBadge {
    case gold, silver, bronze, none
}

extension Calendar {
    /// A calendar pinned to the given IANA timezone (falling back to the
    /// device's current calendar when the id is nil or unknown).
    ///
    /// Day-bucketing for a receiver — "today", streak boundaries, consistency
    /// windows — must be evaluated in the *receiver's* zone so it matches the
    /// server-side dedup and `CheckInService.todayCheckInStatus`. Using the
    /// viewer's device zone made a traveling receiver's streak and badges
    /// disagree with their "checked in today" status by a day.
    static func forTimezone(_ identifier: String?) -> Calendar {
        var calendar = Calendar.current
        if let identifier, let tz = TimeZone(identifier: identifier) {
            calendar.timeZone = tz
        }
        return calendar
    }
}
