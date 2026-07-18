import XCTest
@testable import DailyOK

/// Tests for the receiver schedule resolver (US-IOS047): weekday/weekend,
/// custom per-day, paused, and quiet-hours behavior.
final class ScheduleResolverTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// Build ReceiverSettings via JSON (it only has a Decodable init).
    private func makeSettings(
        scheduleType: String = "daily",
        checkinTime: String = "09:00",
        weekendCheckinTime: String? = nil,
        customSchedule: [String: String]? = nil,
        schedulePaused: Bool = false,
        quietStart: String? = nil,
        quietEnd: String? = nil
    ) -> ReceiverSettings {
        var dict: [String: Any] = [
            "id": UUID().uuidString,
            "family_member_id": UUID().uuidString,
            "checkin_time": checkinTime,
            "timezone": "UTC",
            "grace_period_minutes": 30,
            "reminder_interval_minutes": 15,
            "escalation_enabled": true,
            "mood_tracking_enabled": false,
            "sms_escalation_enabled": false,
            "is_active": true,
            "location_tracking_enabled": false,
            "geofence_radius_meters": 100,
            "location_alert_enabled": false,
            "receiver_mode": "standard",
            "schedule_type": scheduleType,
            "schedule_paused": schedulePaused,
            "notify_owner_on_checkin": true,
            "simple_mode": false,
            "audio_confirmation_enabled": false,
        ]
        if let weekendCheckinTime { dict["weekend_checkin_time"] = weekendCheckinTime }
        if let quietStart { dict["quiet_hours_start"] = quietStart }
        if let quietEnd { dict["quiet_hours_end"] = quietEnd }
        if let customSchedule { dict["custom_schedule"] = customSchedule }

        // swiftlint:disable:next force_try — fixture dict is a compile-time-known
        // literal; a failure here is a broken test, so crashing is correct.
        let data = try! JSONSerialization.data(withJSONObject: dict)
        // swiftlint:disable:next force_try — see above.
        return try! JSONDecoder().decode(ReceiverSettings.self, from: data)
    }

    // 2026-06-10 is a Wednesday, 2026-06-13 a Saturday (UTC).

    func testPausedReturnsNil() {
        let s = makeSettings(schedulePaused: true)
        XCTAssertNil(ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-10T06:00:00Z"), calendar: utc))
    }

    func testDailyNextOccurrence() {
        let s = makeSettings(checkinTime: "09:00")
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-10T06:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-10T09:00:00Z"))
    }

    func testWeekdayWeekendUsesWeekendTimeOnSaturday() {
        let s = makeSettings(scheduleType: "weekday_weekend", checkinTime: "09:00", weekendCheckinTime: "11:00")
        // Saturday morning -> weekend time 11:00.
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-13T06:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-13T11:00:00Z"))
    }

    func testWeekdayWeekendUsesWeekdayTimeOnWednesday() {
        let s = makeSettings(scheduleType: "weekday_weekend", checkinTime: "09:00", weekendCheckinTime: "11:00")
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-10T06:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-10T09:00:00Z"))
    }

    func testCustomScheduleSkipsEmptyWeekendDays() {
        // Weekdays at 08:00, no weekend check-ins. From Saturday it should skip
        // to Monday 08:00.
        let custom = ["mon": "08:00", "tue": "08:00", "wed": "08:00", "thu": "08:00", "fri": "08:00"]
        let s = makeSettings(scheduleType: "custom", customSchedule: custom)
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-13T06:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-15T08:00:00Z")) // Monday
    }

    func testQuietHoursDefersIntoTheClear() {
        // 23:30 check-in with quiet hours 22:00–07:00 (wraps midnight) should be
        // deferred to 07:00 the following morning.
        let s = makeSettings(checkinTime: "23:30", quietStart: "22:00", quietEnd: "07:00")
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-10T06:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-11T07:00:00Z"))
    }

    // MARK: - US-IOS048: multiple windows per day

    /// Build settings whose custom_schedule carries a `multiTimes` map (the new
    /// multi-window shape) alongside legacy single-time fields.
    private func makeMultiTimeSettings(multiTimes: [String: [String]]) -> ReceiverSettings {
        // Dual-written legacy single fields = earliest time of each day.
        var custom: [String: Any] = [:]
        for (day, times) in multiTimes {
            if let earliest = times.sorted().first { custom[day] = earliest }
        }
        custom["multiTimes"] = multiTimes

        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "family_member_id": UUID().uuidString,
            "checkin_time": "09:00",
            "timezone": "UTC",
            "grace_period_minutes": 30,
            "reminder_interval_minutes": 15,
            "escalation_enabled": true,
            "mood_tracking_enabled": false,
            "sms_escalation_enabled": false,
            "is_active": true,
            "location_tracking_enabled": false,
            "geofence_radius_meters": 100,
            "location_alert_enabled": false,
            "receiver_mode": "standard",
            "schedule_type": "custom",
            "schedule_paused": false,
            "notify_owner_on_checkin": true,
            "simple_mode": false,
            "audio_confirmation_enabled": false,
            "custom_schedule": custom,
        ]
        // swiftlint:disable:next force_try — fixture dict is a compile-time-known
        // literal; a failure here is a broken test, so crashing is correct.
        let data = try! JSONSerialization.data(withJSONObject: dict)
        // swiftlint:disable:next force_try — see above.
        return try! JSONDecoder().decode(ReceiverSettings.self, from: data)
    }

    func testMultiWindowResolvesEarliestUpcomingSlot() {
        // Wednesday with 08:00 and 20:00 windows. At 06:00 the next slot is 08:00.
        let s = makeMultiTimeSettings(multiTimes: ["wed": ["08:00", "20:00"]])
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-10T06:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-10T08:00:00Z"))
    }

    func testMultiWindowResolvesSecondSlotAfterFirstPasses() {
        // After 08:00 has passed, the next slot the same day is 20:00.
        let s = makeMultiTimeSettings(multiTimes: ["wed": ["08:00", "20:00"]])
        let next = ReceiverViewModel.nextScheduledCheckIn(for: s, now: date("2026-06-10T09:00:00Z"), calendar: utc)
        XCTAssertEqual(next, date("2026-06-10T20:00:00Z"))
    }

    func testSlotsCountReflectsMultipleWindows() {
        let s = makeMultiTimeSettings(multiTimes: ["wed": ["08:00", "20:00"]])
        XCTAssertEqual(ReceiverViewModel.slotsCount(for: s, on: date("2026-06-10T06:00:00Z"), calendar: utc), 2)
    }

    func testCurrentSlotKeyPicksNearestWindow() {
        let s = makeMultiTimeSettings(multiTimes: ["wed": ["08:00", "20:00"]])
        // 07:50 is nearest the 08:00 window.
        XCTAssertEqual(
            ReceiverViewModel.currentSlotKey(for: s, now: date("2026-06-10T07:50:00Z"), calendar: utc), "08:00")
        // 19:30 is nearest the 20:00 window.
        XCTAssertEqual(
            ReceiverViewModel.currentSlotKey(for: s, now: date("2026-06-10T19:30:00Z"), calendar: utc), "20:00")
    }

    func testCurrentSlotKeyNilForSingleWindow() {
        // A single-window day preserves legacy one-per-day dedup (nil slot key).
        let s = makeSettings(scheduleType: "custom", customSchedule: ["wed": "08:00"])
        XCTAssertNil(ReceiverViewModel.currentSlotKey(for: s, now: date("2026-06-10T07:50:00Z"), calendar: utc))
    }

    // MARK: - US-IOS110: DST + non-UTC coverage

    private var newYork: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// Hour/minute of a Date in the New York calendar — robust to the EST/EDT
    /// offset so these assertions hold across the DST boundary.
    private func nyComponents(_ d: Date) -> (h: Int, m: Int) {
        let c = newYork.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? -1, c.minute ?? -1)
    }

    func testNextOccurrenceLandsOn9amLocalAcrossSpringForward() {
        // 2026-03-08 is US spring-forward (02:00 -> 03:00 EDT). A 09:00 daily
        // check-in must still resolve to 09:00 *local*, not shift by the hour the
        // clocks jumped.
        let s = makeSettings(checkinTime: "09:00")
        let next = ReceiverViewModel.nextScheduledCheckIn(
            for: s, now: date("2026-03-08T10:00:00Z"), calendar: newYork) // 05:00 EST that morning
        XCTAssertNotNil(next)
        XCTAssertEqual(nyComponents(next!).h, 9)
        XCTAssertEqual(nyComponents(next!).m, 0)
    }

    func testNextOccurrenceLandsOn9amLocalAcrossFallBack() {
        // 2026-11-01 is US fall-back (02:00 -> 01:00 EST). 09:00 local must hold.
        let s = makeSettings(checkinTime: "09:00")
        let next = ReceiverViewModel.nextScheduledCheckIn(
            for: s, now: date("2026-11-01T05:00:00Z"), calendar: newYork) // 01:00 EDT that morning
        XCTAssertNotNil(next)
        XCTAssertEqual(nyComponents(next!).h, 9)
        XCTAssertEqual(nyComponents(next!).m, 0)
    }

    func testQuietHoursWrapDefersToMorningInNonUTCZone() {
        // 23:30 local check-in, quiet hours 22:00–07:00 — defer to 07:00 local
        // the next morning, evaluated in New York (non-UTC).
        let s = makeSettings(checkinTime: "23:30", quietStart: "22:00", quietEnd: "07:00")
        let next = ReceiverViewModel.nextScheduledCheckIn(
            for: s, now: date("2026-06-10T20:00:00Z"), calendar: newYork) // 16:00 EDT
        XCTAssertNotNil(next)
        XCTAssertEqual(nyComponents(next!).h, 7)
        XCTAssertEqual(nyComponents(next!).m, 0)
    }
}
