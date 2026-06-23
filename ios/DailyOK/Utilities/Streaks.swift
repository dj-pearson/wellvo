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

    // MARK: - Multiple-windows-per-day variants (US-IOS048)

    /// Number of check-ins recorded per calendar day, parsed from timestamps.
    private static func countsPerDay(_ isoTimestamps: [String], calendar: Calendar) -> [Date: Int] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        var counts: [Date: Int] = [:]
        for iso in isoTimestamps {
            guard let date = formatter.date(from: iso) ?? fallbackFormatter.date(from: iso) else { continue }
            let day = calendar.startOfDay(for: date)
            counts[day, default: 0] += 1
        }
        return counts
    }

    /// Streak that requires all expected windows in a day to be satisfied
    /// (US-IOS048). A day continues the streak only if its check-in count is at
    /// least `expectedPerDay`. With `expectedPerDay <= 1` this matches the
    /// single-window `currentStreak`.
    static func currentStreak(
        isoTimestamps: [String],
        expectedPerDay: Int,
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> Int {
        guard expectedPerDay > 1 else {
            return currentStreak(isoTimestamps: isoTimestamps, calendar: calendar, today: today)
        }
        let counts = countsPerDay(isoTimestamps, calendar: calendar)
        guard !counts.isEmpty else { return 0 }

        func satisfied(_ day: Date) -> Bool { (counts[day] ?? 0) >= expectedPerDay }

        let startOfToday = calendar.startOfDay(for: today)
        // Don't penalize an in-progress today: start from today if it's already
        // satisfied, otherwise from yesterday.
        var cursor = satisfied(startOfToday)
            ? startOfToday
            : calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        var streak = 0
        while satisfied(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Consistency over the last `windowDays`, crediting each day up to
    /// `expectedPerDay` check-ins (US-IOS048). Denominator is
    /// `expectedPerDay * windowDays`; a receiver who hits 2-of-2 windows daily
    /// scores 100%, one who hits 1-of-2 scores 50%. With `expectedPerDay <= 1`
    /// this matches the single-window `consistencyPercent`.
    static func consistencyPercent(
        isoTimestamps: [String],
        expectedPerDay: Int,
        windowDays: Int = 7,
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> Int {
        guard expectedPerDay > 1 else {
            return consistencyPercent(isoTimestamps: isoTimestamps, windowDays: windowDays, calendar: calendar, today: today)
        }
        guard windowDays > 0 else { return 0 }

        let startOfToday = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: startOfToday) else {
            return 0
        }
        let counts = countsPerDay(isoTimestamps, calendar: calendar)

        var satisfied = 0
        for (day, count) in counts where day >= windowStart && day <= startOfToday {
            satisfied += min(count, expectedPerDay)
        }
        let pct = Double(satisfied) / Double(expectedPerDay * windowDays) * 100
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
