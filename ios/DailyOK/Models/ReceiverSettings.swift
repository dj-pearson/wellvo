import Foundation

/// Schedule type for check-in notifications
enum ScheduleType: String, Codable, CaseIterable {
    case daily
    case weekdayWeekend = "weekday_weekend"
    case custom

    var label: String {
        switch self {
        case .daily: return "Every Day"
        case .weekdayWeekend: return "Weekday / Weekend"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .daily: return "Same time every day"
        case .weekdayWeekend: return "Different times for weekdays and weekends"
        case .custom: return "Set individual days and times"
        }
    }
}

/// Per-day schedule for custom schedule type.
///
/// The legacy `mon`..`sun` fields hold a single "HH:mm" time per day. US-IOS048
/// adds `multiTimes` (keyed "mon".."sun" → ["08:00","20:00"]) so a day can have
/// more than one check-in window. This is additive and backward-compatible:
///   * Old clients ignore the unknown `multiTimes` JSON key (Decodable drops
///     extras) and keep reading the single-time fields.
///   * New clients dual-read via `times(forDayKey:)` (prefer the array, fall
///     back to the single field) and dual-write the legacy field (= earliest
///     time) so old clients still see a valid single time.
struct DaySchedule: Codable, Equatable {
    var mon: String?
    var tue: String?
    var wed: String?
    var thu: String?
    var fri: String?
    var sat: String?
    var sun: String?

    /// Multiple times per day, keyed by day ("mon".."sun"). When a day is
    /// present here it supersedes that day's single-time field.
    // Defaulted so the synthesized memberwise init stays source-compatible with
    // existing `DaySchedule(mon:…sun:)` call sites.
    var multiTimes: [String: [String]]? = nil

    static let weekdays: [WritableKeyPath<DaySchedule, String?>] = [\.mon, \.tue, \.wed, \.thu, \.fri]
    static let weekend: [WritableKeyPath<DaySchedule, String?>] = [\.sat, \.sun]
    static let allDays: [(key: String, label: String, keyPath: WritableKeyPath<DaySchedule, String?>)] = [
        ("mon", "Monday", \.mon),
        ("tue", "Tuesday", \.tue),
        ("wed", "Wednesday", \.wed),
        ("thu", "Thursday", \.thu),
        ("fri", "Friday", \.fri),
        ("sat", "Saturday", \.sat),
        ("sun", "Sunday", \.sun),
    ]

    /// The legacy single-time field for a day key.
    func legacyTime(forDayKey key: String) -> String? {
        switch key {
        case "mon": return mon
        case "tue": return tue
        case "wed": return wed
        case "thu": return thu
        case "fri": return fri
        case "sat": return sat
        case "sun": return sun
        default: return nil
        }
    }

    /// All scheduled "HH:mm" times for a day, sorted ascending. Dual-read:
    /// prefers `multiTimes`, falls back to the single legacy field. Empty when
    /// no check-in is scheduled that day.
    func times(forDayKey key: String) -> [String] {
        if let multi = multiTimes?[key], !multi.isEmpty {
            return multi.sorted()
        }
        if let single = legacyTime(forDayKey: key) {
            return [single]
        }
        return []
    }

    static func defaultSchedule(time: String = "08:00") -> DaySchedule {
        DaySchedule(mon: time, tue: time, wed: time, thu: time, fri: time, sat: time, sun: time)
    }
}

struct ReceiverSettings: Codable, Identifiable {
    let id: UUID
    let familyMemberId: UUID
    var checkinTime: String // HH:mm format (weekday time when using weekday_weekend)
    var timezone: String
    var gracePeriodMinutes: Int
    var reminderIntervalMinutes: Int
    var escalationEnabled: Bool
    var quietHoursStart: String? // HH:mm
    var quietHoursEnd: String? // HH:mm
    var moodTrackingEnabled: Bool
    var smsEscalationEnabled: Bool
    var isActive: Bool
    var locationTrackingEnabled: Bool
    var homeLatitude: Double?
    var homeLongitude: Double?
    var geofenceRadiusMeters: Int
    var locationAlertEnabled: Bool
    var receiverMode: ReceiverMode
    var scheduleType: ScheduleType
    var weekendCheckinTime: String? // HH:mm (used with weekday_weekend)
    var customSchedule: DaySchedule?
    var schedulePaused: Bool
    var notifyOwnerOnCheckin: Bool // owner gets a push when this receiver checks in OK
    var simpleMode: Bool // extra-large, low-clutter, emoji-free check-in for seniors
    var audioConfirmationEnabled: Bool // speak/chime a confirmation on check-in

    enum CodingKeys: String, CodingKey {
        case id, timezone
        case familyMemberId = "family_member_id"
        case checkinTime = "checkin_time"
        case gracePeriodMinutes = "grace_period_minutes"
        case reminderIntervalMinutes = "reminder_interval_minutes"
        case escalationEnabled = "escalation_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case moodTrackingEnabled = "mood_tracking_enabled"
        case smsEscalationEnabled = "sms_escalation_enabled"
        case isActive = "is_active"
        case locationTrackingEnabled = "location_tracking_enabled"
        case homeLatitude = "home_latitude"
        case homeLongitude = "home_longitude"
        case geofenceRadiusMeters = "geofence_radius_meters"
        case locationAlertEnabled = "location_alert_enabled"
        case receiverMode = "receiver_mode"
        case scheduleType = "schedule_type"
        case weekendCheckinTime = "weekend_checkin_time"
        case customSchedule = "custom_schedule"
        case schedulePaused = "schedule_paused"
        case notifyOwnerOnCheckin = "notify_owner_on_checkin"
        case simpleMode = "simple_mode"
        case audioConfirmationEnabled = "audio_confirmation_enabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        familyMemberId = try container.decode(UUID.self, forKey: .familyMemberId)
        checkinTime = try container.decode(String.self, forKey: .checkinTime)
        timezone = try container.decode(String.self, forKey: .timezone)
        gracePeriodMinutes = try container.decode(Int.self, forKey: .gracePeriodMinutes)
        reminderIntervalMinutes = try container.decode(Int.self, forKey: .reminderIntervalMinutes)
        escalationEnabled = try container.decode(Bool.self, forKey: .escalationEnabled)
        quietHoursStart = try container.decodeIfPresent(String.self, forKey: .quietHoursStart)
        quietHoursEnd = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd)
        moodTrackingEnabled = try container.decode(Bool.self, forKey: .moodTrackingEnabled)
        smsEscalationEnabled = try container.decode(Bool.self, forKey: .smsEscalationEnabled)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        locationTrackingEnabled = try container.decode(Bool.self, forKey: .locationTrackingEnabled)
        homeLatitude = try container.decodeIfPresent(Double.self, forKey: .homeLatitude)
        homeLongitude = try container.decodeIfPresent(Double.self, forKey: .homeLongitude)
        geofenceRadiusMeters = try container.decode(Int.self, forKey: .geofenceRadiusMeters)
        locationAlertEnabled = try container.decode(Bool.self, forKey: .locationAlertEnabled)
        receiverMode = try container.decodeIfPresent(ReceiverMode.self, forKey: .receiverMode) ?? .standard
        scheduleType = try container.decodeIfPresent(ScheduleType.self, forKey: .scheduleType) ?? .daily
        weekendCheckinTime = try container.decodeIfPresent(String.self, forKey: .weekendCheckinTime)
        customSchedule = try container.decodeIfPresent(DaySchedule.self, forKey: .customSchedule)
        schedulePaused = try container.decodeIfPresent(Bool.self, forKey: .schedulePaused) ?? false
        notifyOwnerOnCheckin = try container.decodeIfPresent(Bool.self, forKey: .notifyOwnerOnCheckin) ?? true
        simpleMode = try container.decodeIfPresent(Bool.self, forKey: .simpleMode) ?? false
        audioConfirmationEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioConfirmationEnabled) ?? false
    }
}

extension ReceiverSettings {
    /// Calendar weekday numbers (1=Sun…7=Sat) on which a check-in is scheduled,
    /// used to judge consistency against the days the receiver was actually
    /// expected to check in. Empty when the schedule is paused (nothing expected);
    /// nil for a custom schedule with no day data so callers fall back to
    /// "every day" (legacy behavior).
    var scheduledWeekdays: Set<Int>? {
        if schedulePaused { return [] }
        switch scheduleType {
        case .daily, .weekdayWeekend:
            return [1, 2, 3, 4, 5, 6, 7]
        case .custom:
            guard let custom = customSchedule else { return nil }
            let keyToWeekday: [String: Int] = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            var set = Set<Int>()
            for (key, weekday) in keyToWeekday where !custom.times(forDayKey: key).isEmpty {
                set.insert(weekday)
            }
            return set
        }
    }
}
