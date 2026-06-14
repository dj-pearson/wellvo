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

        let data = try! JSONSerialization.data(withJSONObject: dict)
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
}
