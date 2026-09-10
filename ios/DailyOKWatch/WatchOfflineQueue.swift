import Foundation

/// Offline queue for wrist check-ins made while the watch had no network and the
/// phone was unreachable.
///
/// It used to be a single slot holding one marker for "today", on the reasoning
/// that the server dedupes per local day so one marker per day is all that is
/// needed. The reasoning was right; the implementation lost check-ins at the
/// edges:
///
///  - A marker stamped at 23:55 that had not flushed by midnight was read as
///    stale and cleared. The receiver had already been shown the success haptic
///    and the "all set" screen, so a check-in they genuinely made was discarded
///    silently — and the owner then escalated on it.
///  - With one slot, a tap on a new day while yesterday's was still pending had
///    nowhere to go.
///
/// Both are fixed by keeping one marker per day, each stamped with the moment it
/// was made, and sending that moment as `occurred_at` (US-IOS147) so the server
/// files it under the day it belongs to rather than the day it arrives.
enum WatchOfflineQueue {
    private static let markersKey = "watch_pending_checkins"
    /// The single-slot keys this replaces. Read once, migrated, then removed —
    /// an upgrade must not drop a check-in that is already waiting.
    private static let legacyKey = "watch_pending_checkin"
    private static let legacyTypeKey = "watch_pending_checkin_type"

    // MARK: - Reading

    /// Every pending check-in, oldest first, with anything past the replay window
    /// already dropped. Reading prunes, so a stale marker never lingers.
    static var pending: [OfflineCheckInMarker] {
        let raw = loadRaw()
        let pruned = OfflineMarkerPolicy.prune(raw)
        if pruned != raw { save(pruned) }
        return pruned
    }

    /// Whether anything is waiting to send.
    static var hasPending: Bool { !pending.isEmpty }

    /// Whether *today* is already answered by something in the queue. This is
    /// the one a glanceable surface wants: a marker from yesterday is real and
    /// will be sent, but it does not mean today is done.
    static var hasPendingForToday: Bool {
        OfflineMarkerPolicy.hasMarker(pending, onSameDayAs: Date())
    }

    /// When the oldest pending check-in was made.
    static var pendingSince: Date? { pending.first?.at }

    /// The queued response type for today, defaulting to "ok".
    static var pendingType: String {
        pending.last(where: { Calendar.current.isDateInToday($0.at) })?.type ?? "ok"
    }

    // MARK: - Writing

    /// Queue a pending response for now.
    static func enqueue(type: String = "ok") {
        let marker = OfflineCheckInMarker(at: Date(), type: type)
        save(OfflineMarkerPolicy.enqueue(loadRaw(), adding: marker))
    }

    /// Remove a marker that has been sent.
    static func remove(_ marker: OfflineCheckInMarker) {
        save(loadRaw().filter { $0 != marker })
    }

    /// Remove only the marker answering today, leaving earlier days queued.
    ///
    /// A live check-in that succeeds settles TODAY. It says nothing about a tap
    /// from a previous day that never reached the server — clearing the whole
    /// queue there would throw that one away, which is the loss this queue was
    /// rewritten to stop.
    static func clearToday(calendar: Calendar = .current) {
        save(loadRaw().filter { !calendar.isDateInToday($0.at) })
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: markersKey)
        SharedAppGroup.defaults?.removeObject(forKey: legacyKey)
        SharedAppGroup.defaults?.removeObject(forKey: legacyTypeKey)
    }

    // MARK: - Storage

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func loadRaw() -> [OfflineCheckInMarker] {
        guard let defaults = SharedAppGroup.defaults else { return [] }

        var markers: [OfflineCheckInMarker] = []
        if let data = defaults.data(forKey: markersKey),
           let decoded = try? decoder.decode([OfflineCheckInMarker].self, from: data) {
            markers = decoded
        }

        // One-time migration from the single slot. Done on read rather than at
        // launch so it cannot be missed by a surface that never runs launch code
        // (the notification controller queues from a background wake).
        if let stamped = defaults.object(forKey: legacyKey) as? Date {
            let type = defaults.string(forKey: legacyTypeKey) ?? "ok"
            markers = OfflineMarkerPolicy.enqueue(
                markers,
                adding: OfflineCheckInMarker(at: stamped, type: type)
            )
            defaults.removeObject(forKey: legacyKey)
            defaults.removeObject(forKey: legacyTypeKey)
            save(markers)
        }

        return markers
    }

    private static func save(_ markers: [OfflineCheckInMarker]) {
        guard let defaults = SharedAppGroup.defaults else { return }
        guard !markers.isEmpty else {
            defaults.removeObject(forKey: markersKey)
            return
        }
        guard let data = try? encoder.encode(markers) else { return }
        defaults.set(data, forKey: markersKey)
    }
}
