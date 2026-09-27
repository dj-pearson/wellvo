import Foundation

/// Schedule type for check-in notifications
enum ScheduleType: String, Codable, CaseIterable {
    case daily
    case weekdayWeekend = "weekday_weekend"
    case custom

    // Forgiving decode: `decodeIfPresent(...) ?? .daily` at the call site only
    // tolerates a missing/null value — a present but unknown `schedule_type`
    // (e.g. a future "biweekly") still threw, and because settings decode as an
    // array, one unknown value dropped schedule-awareness for every receiver in
    // the batch. Unknown → `.daily`. No new case, so the picker is unchanged.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScheduleType(rawValue: raw) ?? .daily
    }

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
struct DaySchedule: Codable, Equatable, Sendable {
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
    /// When a pause ends by itself (00056). Nil = paused until someone resumes,
    /// or not paused. Older servers don't send it.
    var pausedUntil: Date?
    /// True when `custom_schedule` arrived as a JSON *string* holding the
    /// object — what iOS builds before 2026-09-27 wrote. Dispatch can't read
    /// that shape, so the settings screen rewrites it as an object. Not coded.
    var customScheduleNeedsRepair = false

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
        case pausedUntil = "paused_until"
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
        // Dual-read: an object (correct), or a string holding the object's JSON
        // (written by older iOS builds). A string used to throw here, which
        // failed the whole row — and, because the dashboard decodes settings
        // as an array, every receiver's schedule. Anything else unreadable is
        // treated as "no custom schedule" rather than failing the row.
        if let schedule = try? container.decodeIfPresent(DaySchedule.self, forKey: .customSchedule) {
            customSchedule = schedule
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .customSchedule),
                  let data = raw.data(using: .utf8),
                  let schedule = try? JSONDecoder().decode(DaySchedule.self, from: data) {
            customSchedule = schedule
            customScheduleNeedsRepair = true
        } else {
            customSchedule = nil
        }
        schedulePaused = try container.decodeIfPresent(Bool.self, forKey: .schedulePaused) ?? false
        notifyOwnerOnCheckin = try container.decodeIfPresent(Bool.self, forKey: .notifyOwnerOnCheckin) ?? true
        simpleMode = try container.decodeIfPresent(Bool.self, forKey: .simpleMode) ?? false
        audioConfirmationEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioConfirmationEnabled) ?? false
        // Read as text so the result doesn't depend on the decoder's date
        // strategy (Postgres sends "2026-09-28T07:00:00+00:00").
        let pausedUntilRaw = try? container.decodeIfPresent(String.self, forKey: .pausedUntil)
        pausedUntil = pausedUntilRaw.flatMap { ReceiverSettingsForm.parseTimestamp($0) }
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

// MARK: - Owner edits

/// The owner-editable part of `receiver_settings`, in wire format ("HH:mm"
/// times, a real `DaySchedule`). The settings screen snapshots this right after
/// a load and diffs against it, so Save sends only what the owner changed — a
/// receiver's own Simple Mode / Spoken Confirmation choices are never
/// overwritten by an owner who didn't touch them — and Back can warn about
/// unsaved edits.
struct ReceiverSettingsForm: Equatable {
    var checkinTime: String
    var gracePeriodMinutes: Int
    var reminderIntervalMinutes: Int
    var escalationEnabled: Bool
    var moodTrackingEnabled: Bool
    var smsEscalationEnabled: Bool
    var notifyOwnerOnCheckin: Bool
    var receiverMode: ReceiverMode
    var scheduleType: ScheduleType
    var schedulePaused: Bool
    /// Only meaningful while paused; nil = until someone resumes.
    var pausedUntil: Date?
    var simpleMode: Bool
    var audioConfirmationEnabled: Bool
    /// Only meaningful for `.weekdayWeekend`.
    var weekendCheckinTime: String?
    /// Only meaningful for `.custom`.
    var customSchedule: DaySchedule?
    /// Both set, or both nil (quiet hours off).
    var quietHoursStart: String?
    var quietHoursEnd: String?

    /// The PATCH body for this form. With no `original`, every field is sent.
    /// Otherwise only changed fields. Schedule details are sent when the
    /// schedule type is the one that uses them and either they or the type
    /// changed. Quiet hours are sent as a pair so they are never half-cleared.
    func patch(from original: ReceiverSettingsForm?) -> ReceiverSettingsPatch {
        var p = ReceiverSettingsPatch()
        func changed<T: Equatable>(_ kp: KeyPath<ReceiverSettingsForm, T>) -> Bool {
            guard let original else { return true }
            return original[keyPath: kp] != self[keyPath: kp]
        }
        if changed(\.checkinTime) { p.set("checkin_time", .string(checkinTime)) }
        if changed(\.gracePeriodMinutes) { p.set("grace_period_minutes", .int(gracePeriodMinutes)) }
        if changed(\.reminderIntervalMinutes) { p.set("reminder_interval_minutes", .int(reminderIntervalMinutes)) }
        if changed(\.escalationEnabled) { p.set("escalation_enabled", .bool(escalationEnabled)) }
        if changed(\.moodTrackingEnabled) { p.set("mood_tracking_enabled", .bool(moodTrackingEnabled)) }
        if changed(\.smsEscalationEnabled) { p.set("sms_escalation_enabled", .bool(smsEscalationEnabled)) }
        if changed(\.notifyOwnerOnCheckin) { p.set("notify_owner_on_checkin", .bool(notifyOwnerOnCheckin)) }
        if changed(\.receiverMode) { p.set("receiver_mode", .string(receiverMode.rawValue)) }
        if changed(\.scheduleType) { p.set("schedule_type", .string(scheduleType.rawValue)) }
        if changed(\.schedulePaused) { p.set("schedule_paused", .bool(schedulePaused)) }
        if changed(\.simpleMode) { p.set("simple_mode", .bool(simpleMode)) }
        if changed(\.audioConfirmationEnabled) { p.set("audio_confirmation_enabled", .bool(audioConfirmationEnabled)) }

        // paused_until only means something while paused. Sent only when it
        // changes, so a save on a server without the column (pre-00056)
        // fails only if the owner actually chose an end date.
        let effectivePausedUntil: Date? = schedulePaused ? pausedUntil : nil
        var originalPausedUntil: Date?
        if let original, original.schedulePaused { originalPausedUntil = original.pausedUntil }
        let pauseEndChanged = original == nil
            ? effectivePausedUntil != nil
            : effectivePausedUntil != originalPausedUntil
        if pauseEndChanged {
            if let end = effectivePausedUntil {
                p.set("paused_until", .string(Self.timestampString(end)))
            } else {
                p.set("paused_until", .null)
            }
        }

        switch scheduleType {
        case .weekdayWeekend:
            if let weekend = weekendCheckinTime, changed(\.weekendCheckinTime) || changed(\.scheduleType) {
                p.set("weekend_checkin_time", .string(weekend))
            }
        case .custom:
            if let schedule = customSchedule, changed(\.customSchedule) || changed(\.scheduleType) {
                p.set("custom_schedule", .schedule(schedule))
            }
        case .daily:
            break
        }

        if changed(\.quietHoursStart) || changed(\.quietHoursEnd) {
            if let start = quietHoursStart, let end = quietHoursEnd {
                p.set("quiet_hours_start", .string(start))
                p.set("quiet_hours_end", .string(end))
            } else {
                // Explicit nulls so turning Quiet Hours off actually persists.
                p.set("quiet_hours_start", .null)
                p.set("quiet_hours_end", .null)
            }
        }
        return p
    }

    // MARK: Schedule checks

    /// Every "HH:mm" time the current schedule would dispatch, de-duplicated
    /// and sorted.
    var scheduledTimes: [String] {
        let times: [String]
        switch scheduleType {
        case .daily:
            times = [checkinTime]
        case .weekdayWeekend:
            times = [checkinTime, weekendCheckinTime ?? checkinTime]
        case .custom:
            let schedule = customSchedule ?? DaySchedule()
            times = DaySchedule.allDays.flatMap { schedule.times(forDayKey: $0.key) }
        }
        return Array(Set(times.map(Self.normalizedHHmm))).sorted()
    }

    /// Scheduled times that fall inside quiet hours. Dispatch sends nothing
    /// while quiet hours are on (00052), so such a check-in is not asked at its
    /// time — before 00056 it was dropped for the day, with no escalation.
    /// Half-open [start, end), wrapping midnight — the receiver app's rule.
    var timesInsideQuietHours: [String] {
        guard let qs = quietHoursStart.flatMap(Self.minutesOfDay),
              let qe = quietHoursEnd.flatMap(Self.minutesOfDay),
              qs != qe else { return [] }
        return scheduledTimes.filter { time in
            guard let m = Self.minutesOfDay(time) else { return false }
            return Self.isInQuietHours(m, start: qs, end: qe)
        }
    }

    static func isInQuietHours(_ minute: Int, start: Int, end: Int) -> Bool {
        if start < end { return minute >= start && minute < end }
        if start > end { return minute >= start || minute < end }
        return false
    }

    /// "08:00" / "08:00:00" → 480. Nil when unparseable.
    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    private static func normalizedHHmm(_ time: String) -> String {
        guard let m = minutesOfDay(time) else { return time }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    // MARK: Escalation timeline

    enum EscalationStepKind: Equatable {
        case asked, reminder, ownerAlerted, viewersAlerted, missed
    }

    /// What escalation does after a check-in is asked and not answered, as
    /// minutes after the ask. Mirrors escalation_tick (00052): the first step
    /// fires after the grace period, each later step one reminder interval
    /// apart, and after step 3 the request is marked missed.
    static func escalationSteps(gracePeriodMinutes grace: Int, reminderIntervalMinutes interval: Int)
        -> [(offsetMinutes: Int, kind: EscalationStepKind)] {
        [
            (0, .asked),
            (grace, .reminder),
            (grace + interval, .ownerAlerted),
            (grace + 2 * interval, .viewersAlerted),
            (grace + 3 * interval, .missed),
        ]
    }

    // MARK: Pause

    enum PauseLength: String, CaseIterable, Identifiable {
        case untilResumed, tomorrow, threeDays, oneWeek, onDate
        var id: String { rawValue }

        var label: String {
            switch self {
            case .untilResumed: return String(localized: "Until I turn it back on")
            case .tomorrow: return String(localized: "Just today")
            case .threeDays: return String(localized: "For 3 days")
            case .oneWeek: return String(localized: "For a week")
            case .onDate: return String(localized: "Until a date…")
            }
        }
    }

    /// When a pause of `length` ends: the start of the resume day in the
    /// receiver's calendar, so "Just today" resumes at their midnight and
    /// tomorrow's check-in goes out. Nil for `.untilResumed`. For `.onDate`
    /// the chosen day's year/month/day are taken as-is.
    static func resumeDate(for length: PauseLength, now: Date, chosenDay: Date,
                           receiverCalendar: Calendar, pickerCalendar: Calendar = .current) -> Date? {
        let startOfToday = receiverCalendar.startOfDay(for: now)
        switch length {
        case .untilResumed:
            return nil
        case .tomorrow:
            return receiverCalendar.date(byAdding: .day, value: 1, to: startOfToday)
        case .threeDays:
            return receiverCalendar.date(byAdding: .day, value: 3, to: startOfToday)
        case .oneWeek:
            return receiverCalendar.date(byAdding: .day, value: 7, to: startOfToday)
        case .onDate:
            let ymd = pickerCalendar.dateComponents([.year, .month, .day], from: chosenDay)
            return receiverCalendar.date(from: ymd)
        }
    }

    // MARK: Timestamps

    static func timestampString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Postgres timestamptz text, with or without fractional seconds.
    static func parseTimestamp(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: raw) { return d }
        // Postgres may use a space separator.
        let t = raw.replacingOccurrences(of: " ", with: "T")
        if t != raw { return parseTimestamp(t) }
        return nil
    }
}

/// A partial `receiver_settings` update. Encodes a real JSON object for
/// `custom_schedule` — older builds sent a pre-stringified JSON *string*,
/// which PostgREST stores verbatim in the jsonb column, so dispatch never
/// matched a day and no custom-schedule check-in was ever sent — and explicit
/// nulls where a column must be cleared.
struct ReceiverSettingsPatch: Encodable, Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case schedule(DaySchedule)
        case null
    }

    private(set) var fields: [String: Value] = [:]

    var isEmpty: Bool { fields.isEmpty }

    mutating func set(_ key: String, _ value: Value) { fields[key] = value }
    mutating func remove(_ key: String) { fields[key] = nil }
    subscript(key: String) -> Value? { fields[key] }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            let key = Key(name)
            switch value {
            case .string(let v): try c.encode(v, forKey: key)
            case .int(let v): try c.encode(v, forKey: key)
            case .bool(let v): try c.encode(v, forKey: key)
            case .schedule(let v): try c.encode(v, forKey: key)
            case .null: try c.encodeNil(forKey: key)
            }
        }
    }
}
