import Foundation

/// Glanceable owner snapshot published to the shared App Group so the owner
/// status widget can render every receiver's check-in state without a network
/// round-trip or a live app session.
struct SharedOwnerReceiver: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// "checked_in" | "pending" | "missed" | "no_data"
    var status: String
    var lastCheckInAt: Date?

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
    func status(asOf now: Date = Date(), calendar: Calendar = .current) -> String {
        guard status == "checked_in" else { return status }
        guard let lastCheckInAt, calendar.isDate(lastCheckInAt, inSameDayAs: now) else {
            return "pending"
        }
        return status
    }

    /// The check-in time, only when it belongs to `now`'s day — so a stale
    /// timestamp is never rendered as today's.
    func lastCheckIn(asOf now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let lastCheckInAt, calendar.isDate(lastCheckInAt, inSameDayAs: now) else { return nil }
        return lastCheckInAt
    }
}

struct SharedOwnerState: Codable, Equatable {
    var receivers: [SharedOwnerReceiver]
    var updatedAt: Date

    var total: Int { receivers.count }

    /// Day-scoped, for the reason on `SharedOwnerReceiver.status(asOf:)`: "3 of
    /// 3 checked in" carried over from yesterday is worse than no widget.
    func checkedInCount(asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        receivers.filter { $0.status(asOf: now, calendar: calendar) == "checked_in" }.count
    }

    /// The receiver an owner most wants to see first: a missed one, else a
    /// pending one, else the first. Ordered on the day-scoped status so a
    /// stale "checked in" cannot outrank someone who genuinely has not answered.
    func mostRelevant(asOf now: Date = Date(), calendar: Calendar = .current) -> SharedOwnerReceiver? {
        receivers.first(where: { $0.status(asOf: now, calendar: calendar) == "missed" })
            ?? receivers.first(where: { $0.status(asOf: now, calendar: calendar) == "pending" })
            ?? receivers.first
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
