import Foundation

/// Glanceable owner snapshot published to the shared App Group so the owner
/// status widget can render every receiver's check-in state without a network
/// round-trip or a live app session.
struct SharedOwnerReceiver: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// "checked_in" | "pending" | "missed" | "no_data" | "needs_help" |
    /// "upcoming" (nothing due yet today)
    var status: String
    var lastCheckInAt: Date?
    /// When `status` was computed. Optional so snapshots written by older
    /// builds still decode. Used to day-scope "upcoming".
    var statusDate: Date? = nil
    /// The owner stood the escalation down ("I reached her"). The dashboard
    /// shows "Alerts stopped"; the widget kept showing red "Missed" and
    /// featured this person over one still escalating. Optional: older
    /// snapshots decode as not stood down.
    var stoodDown: Bool? = nil
    /// For "needs_help": "need_help" | "call_me" | "sos".
    var helpKind: String? = nil
    /// The receiver's zone. The server files check-ins by it and the dashboard
    /// shows times in it; the widget used the owner's device zone, so Dad's
    /// 11 PM Monday check-in in Los Angeles read as Tuesday's in New York.
    var timeZoneId: String? = nil
    /// "Tom is on it" — the co-caregiver who claimed today's alert.
    var claimedByName: String? = nil

    /// The calendar "today" means for this person.
    var receiverCalendar: Calendar {
        var cal = Calendar.current
        if let id = timeZoneId, let zone = TimeZone(identifier: id) { cal.timeZone = zone }
        return cal
    }

    /// The status as it stands on `now`, rather than as it stood when the
    /// snapshot was written.
    ///
    /// Only the phone app writes this snapshot. If the owner does not open it —
    /// overnight, or for a day, or with background refresh switched off — the
    /// widget keeps rendering whatever was true when they last did. A stale
    /// "checked in ✓" beside a relative's name is the precise false
    /// reassurance this product exists to prevent: the owner glances, sees a
    /// green tick, and stops wondering, on a day that has not been answered.
    ///
    /// So a `checked_in` whose `lastCheckInAt` is not today reverts to
    /// `pending` — "we do not know yet", which is the truth. The receiver
    /// widget has always been day-scoped this way (`SharedCheckInState
    /// .isCheckedIn(asOf:)`); the owner's was not.
    ///
    /// Deliberately never promotes to "missed": whether a window has elapsed is
    /// the server's call, and a widget guessing it would invent an escalation
    /// nobody raised.
    ///
    /// "needs_help" is day-scoped the same way (it IS today's check-in, one
    /// that asked for help), and so is "upcoming": "not due yet" computed
    /// yesterday says nothing about today.
    ///
    /// "stood_down" (derived, never published): a missed/pending status the
    /// owner stood down today. Neutral, not an alarm, and no longer the person
    /// the widget features. Yesterday's stand-down says nothing about today.
    ///
    /// `calendar` overrides the zone (tests); nil uses the receiver's zone.
    func status(asOf now: Date = Date(), calendar: Calendar? = nil) -> String {
        let calendar = calendar ?? receiverCalendar
        switch status {
        case "checked_in", "needs_help":
            guard let lastCheckInAt, calendar.isDate(lastCheckInAt, inSameDayAs: now) else {
                return "pending"
            }
            return status
        case "upcoming":
            guard let statusDate, calendar.isDate(statusDate, inSameDayAs: now) else {
                return "pending"
            }
            return status
        case "missed", "pending", "no_data":
            if stoodDown == true {
                guard let statusDate, calendar.isDate(statusDate, inSameDayAs: now) else {
                    return "pending"
                }
                return "stood_down"
            }
            return status
        default:
            return status
        }
    }

    /// The check-in time, only when it belongs to `now`'s day — so a stale
    /// timestamp is never rendered as today's.
    func lastCheckIn(asOf now: Date = Date(), calendar: Calendar? = nil) -> Date? {
        let calendar = calendar ?? receiverCalendar
        guard let lastCheckInAt, calendar.isDate(lastCheckInAt, inSameDayAs: now) else { return nil }
        return lastCheckInAt
    }

    /// "8:15 AM" in the receiver's zone, with the zone's abbreviation when it
    /// differs from the viewer's ("8:15 AM PDT") so it matches the dashboard.
    func timeText(_ date: Date, viewerZone: TimeZone = .current) -> String {
        let zone = receiverCalendar.timeZone
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = zone
        let time = formatter.string(from: date)
        guard zone.secondsFromGMT(for: date) != viewerZone.secondsFromGMT(for: date),
              let abbreviation = zone.abbreviation(for: date) else { return time }
        return "\(time) \(abbreviation)"
    }

    /// Words for a status, for the widget's rows and VoiceOver.
    func label(forStatus status: String) -> String {
        switch status {
        case "checked_in": return "Checked in"
        case "pending": return "Pending"
        case "missed": return "Missed"
        case "stood_down": return "Alerts stopped"
        case "needs_help":
            switch helpKind {
            case "call_me": return "Asked you to call"
            case "sos": return "Sent SOS"
            default: return "Needs help"
            }
        case "upcoming": return "Not due yet"
        default: return "No check-in yet"
        }
    }
}

struct SharedOwnerState: Codable, Equatable {
    var receivers: [SharedOwnerReceiver]
    var updatedAt: Date

    var total: Int { receivers.count }

    /// Day-scoped, for the reason on `SharedOwnerReceiver.status(asOf:)`: "3 of
    /// 3 checked in" carried over from yesterday is worse than no widget.
    func checkedInCount(asOf now: Date = Date(), calendar: Calendar? = nil) -> Int {
        receivers.filter { $0.status(asOf: now, calendar: calendar) == "checked_in" }.count
    }

    /// The receiver an owner most wants to see first: an SOS, else one who
    /// asked for help, else a missed one (not stood down), else a pending one,
    /// else the first. Ordered on the day-scoped status so a stale "checked in"
    /// cannot outrank someone who genuinely has not answered, and a miss the
    /// owner already handled cannot outrank one still escalating.
    func mostRelevant(asOf now: Date = Date(), calendar: Calendar? = nil) -> SharedOwnerReceiver? {
        receivers.first(where: { $0.status(asOf: now, calendar: calendar) == "needs_help" && $0.helpKind == "sos" })
            ?? receivers.first(where: { $0.status(asOf: now, calendar: calendar) == "needs_help" })
            ?? receivers.first(where: { $0.status(asOf: now, calendar: calendar) == "missed" })
            ?? receivers.first(where: { $0.status(asOf: now, calendar: calendar) == "pending" })
            ?? receivers.first
    }

    /// Whether anything on the widget still wants the owner's attention.
    func needsAttention(asOf now: Date = Date(), calendar: Calendar? = nil) -> Bool {
        receivers.contains {
            let status = $0.status(asOf: now, calendar: calendar)
            return status == "missed" || status == "pending" || status == "needs_help"
        }
    }

    /// The Lock Screen headline: who needs the owner, by name, or nil when the
    /// count says it all. "2 of 3 checked in" read the same on a slow morning
    /// and on the morning Mom asked for help.
    func headline(asOf now: Date = Date(), calendar: Calendar? = nil) -> String? {
        guard let r = mostRelevant(asOf: now, calendar: calendar) else { return nil }
        switch r.status(asOf: now, calendar: calendar) {
        case "needs_help":
            switch r.helpKind {
            case "call_me": return "\(r.name) asked you to call"
            case "sos": return "\(r.name) sent an SOS"
            default: return "\(r.name) needs help"
            }
        case "missed": return "No answer from \(r.name)"
        default: return nil
        }
    }
}

enum SharedOwnerStore {
    private static let key = "shared_owner_state"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    static func load() -> SharedOwnerState? {
        guard let data = SharedAppGroup.defaults?.data(forKey: key) else { return nil }
        return try? decoder.decode(SharedOwnerState.self, from: data)
    }

    static func save(_ state: SharedOwnerState) {
        guard let data = try? encoder.encode(state) else { return }
        SharedAppGroup.defaults?.set(data, forKey: key)
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: key)
    }
}
