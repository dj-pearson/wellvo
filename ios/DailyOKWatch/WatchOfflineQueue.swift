import Foundation

/// A one-slot offline queue for a wrist check-in made while the watch had no
/// network and the phone was unreachable. We only need a single pending marker
/// per day: the server dedupes check-ins per local day, so flushing a stale
/// marker after the phone already checked in simply returns the existing row —
/// never a duplicate.
enum WatchOfflineQueue {
    private static let key = "watch_pending_checkin"
    private static let typeKey = "watch_pending_checkin_type"

    /// A pending marker only counts if it was stamped *today* (local day). A
    /// marker left over from a previous day is stale — the day already rolled
    /// over, so it would make today falsely look already-checked-in. Reading it
    /// here clears the stale marker (US-IOS090).
    static var hasPending: Bool {
        guard let stamped = SharedAppGroup.defaults?.object(forKey: key) as? Date else { return false }
        if Calendar.current.isDateInToday(stamped) { return true }
        clear()
        return false
    }

    /// When the pending check-in was first attempted (for display/debugging).
    static var pendingSince: Date? {
        SharedAppGroup.defaults?.object(forKey: key) as? Date
    }

    /// The queued response type ("ok" / "need_help" / "call_me"). Defaults to
    /// "ok" for a legacy marker written before the type was stored, so an
    /// upgrade-in-place still flushes correctly (US-IOS119).
    static var pendingType: String {
        SharedAppGroup.defaults?.string(forKey: typeKey) ?? "ok"
    }

    /// Queue a pending response. If an "ok" is already queued and a more urgent
    /// help/call response arrives offline, upgrade the stored type in place (the
    /// single slot must never downgrade an urgent request to a plain OK, nor
    /// drop it entirely as the old code did).
    static func enqueue(type: String = "ok") {
        if hasPending {
            if pendingType == "ok", type != "ok" {
                SharedAppGroup.defaults?.set(type, forKey: typeKey)
            }
            return
        }
        SharedAppGroup.defaults?.set(Date(), forKey: key)
        SharedAppGroup.defaults?.set(type, forKey: typeKey)
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: key)
        SharedAppGroup.defaults?.removeObject(forKey: typeKey)
    }
}
