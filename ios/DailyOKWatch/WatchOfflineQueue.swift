import Foundation

/// A one-slot offline queue for a wrist check-in made while the watch had no
/// network and the phone was unreachable. We only need a single pending marker
/// per day: the server dedupes check-ins per local day, so flushing a stale
/// marker after the phone already checked in simply returns the existing row —
/// never a duplicate.
enum WatchOfflineQueue {
    private static let key = "watch_pending_checkin"

    static var hasPending: Bool {
        SharedAppGroup.defaults?.object(forKey: key) != nil
    }

    /// When the pending check-in was first attempted (for display/debugging).
    static var pendingSince: Date? {
        SharedAppGroup.defaults?.object(forKey: key) as? Date
    }

    static func enqueue() {
        guard !hasPending else { return }
        SharedAppGroup.defaults?.set(Date(), forKey: key)
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: key)
    }
}
