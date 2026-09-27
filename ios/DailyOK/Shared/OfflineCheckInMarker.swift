import Foundation

/// A check-in the receiver made while the device could not reach the server,
/// held until it can be sent.
///
/// Used by the watch's offline queue. Kept in `Shared/` and free of any storage
/// or networking dependency so the decisions below — which are the part that
/// can silently lose someone's check-in — are pure and testable.
struct OfflineCheckInMarker: Equatable, Codable {
    /// When the receiver actually tapped. Sent as `occurred_at` so the server
    /// files the check-in under the day it was made rather than the day it
    /// arrived (US-IOS147).
    var at: Date
    /// `ok` / `need_help` / `call_me`.
    var type: String
    /// Whose tap this is. Optional so a queue written by an older build still
    /// decodes; nil means "from before markers were stamped" (see
    /// `OfflineMarkerPolicy.belongs`). Without it a watch or phone handed to
    /// the next family member sent the previous person's queued taps as the
    /// new person's check-ins.
    var receiverId: String? = nil
    var familyId: String? = nil
    /// The surface that took the tap ("widget" / "control" / "siri" / "watch"),
    /// replayed as the check-in's source.
    var source: String? = nil
    /// The "HH:mm" window the tap answered, when known.
    var slotKey: String? = nil
}

/// Pure rules for a queue of pending check-ins.
enum OfflineMarkerPolicy {

    /// Matches `OfflineCheckInService.maxReplayAge` and the server's
    /// `OCCURRED_AT_MAX_AGE_MS`. Past this bound the server stops honouring a
    /// client timestamp and files the check-in under today, which would tell the
    /// owner the receiver is fine right now.
    static let maxReplayAge: TimeInterval = 7 * 24 * 60 * 60

    /// A hard cap so a device that is offline for a long stretch cannot grow the
    /// queue without bound. One marker per day and a seven-day window already
    /// bound it to 8; this is the belt.
    static let maxMarkers = 14

    /// An urgent response must never be downgraded to a plain OK when two taps
    /// collapse into one day's marker.
    static func isUrgent(_ type: String) -> Bool { type != "ok" }

    /// Whether a marker is still young enough for the server to file correctly.
    static func isReplayable(_ marker: OfflineCheckInMarker, now: Date = Date()) -> Bool {
        now.timeIntervalSince(marker.at) <= maxReplayAge && marker.at <= now
    }

    /// Drop markers the server would no longer file under the right day.
    static func prune(_ markers: [OfflineCheckInMarker], now: Date = Date()) -> [OfflineCheckInMarker] {
        markers.filter { isReplayable($0, now: now) }.sorted { $0.at < $1.at }
    }

    /// Add a tap to the queue.
    ///
    /// One marker per local day. A second tap on a day already queued is the
    /// same check-in — the receiver not seeing confirmation and trying again —
    /// so it does not add a row, but it does upgrade the stored type if the new
    /// tap is urgent. The timestamp stays at the FIRST tap, which is the moment
    /// the receiver actually answered.
    ///
    /// A tap on a *different* day is a different check-in and must survive. The
    /// single-slot queue this replaces dropped it: a tap at 23:55 that had not
    /// flushed by midnight was discarded, silently, after the watch had already
    /// played the success haptic and told the receiver they were done.
    static func enqueue(
        _ markers: [OfflineCheckInMarker],
        adding marker: OfflineCheckInMarker,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [OfflineCheckInMarker] {
        var result = prune(markers, now: now)

        if let index = result.firstIndex(where: { calendar.isDate($0.at, inSameDayAs: marker.at) }) {
            if isUrgent(marker.type) && !isUrgent(result[index].type) {
                result[index].type = marker.type
            }
            return result
        }

        result.append(marker)
        result.sort { $0.at < $1.at }
        if result.count > maxMarkers {
            // Drop the oldest: they are the ones closest to falling outside the
            // replay window anyway.
            result.removeFirst(result.count - maxMarkers)
        }
        return result
    }

    /// Whether the queue holds a check-in for the given local day — what a
    /// glanceable surface should show as "sent, waiting".
    static func hasMarker(
        _ markers: [OfflineCheckInMarker],
        onSameDayAs date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        markers.contains { calendar.isDate($0.at, inSameDayAs: date) }
    }

    /// Whether a marker may be sent as `receiverId`.
    ///
    /// A stamped marker belongs only to the person who made it. An unstamped
    /// one was written by a build that didn't stamp; it is treated as the
    /// current person's, because the only way to have one is to have tapped on
    /// this device before updating — and the queue is now cleared on sign-out,
    /// so a hand-over can no longer leave one behind.
    static func belongs(_ marker: OfflineCheckInMarker, to receiverId: String) -> Bool {
        guard let owner = marker.receiverId else { return true }
        return owner.lowercased() == receiverId.lowercased()
    }

    /// Split a queue into what may be sent for `receiverId` and what must be
    /// dropped (another person's taps).
    static func partition(
        _ markers: [OfflineCheckInMarker],
        for receiverId: String
    ) -> (mine: [OfflineCheckInMarker], foreign: [OfflineCheckInMarker]) {
        var mine: [OfflineCheckInMarker] = []
        var foreign: [OfflineCheckInMarker] = []
        for marker in markers {
            if belongs(marker, to: receiverId) { mine.append(marker) } else { foreign.append(marker) }
        }
        return (mine, foreign)
    }
}

/// App Group persistence for marker queues. Shared so the watch app, the watch
/// complication, the phone's widget / Control Center / Siri intent and the
/// phone app all read the same bytes the same way.
enum OfflineMarkerStore {
    /// The watch's queue of wrist taps (WatchOfflineQueue).
    static let watchKey = "watch_pending_checkins"
    /// The phone's queue of widget / Control Center / Siri taps that couldn't
    /// reach the server. Drained by the app (OfflineCheckInService).
    static let extensionKey = "extension_pending_checkins"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load(key: String) -> [OfflineCheckInMarker] {
        guard let data = SharedAppGroup.defaults?.data(forKey: key),
              let decoded = try? decoder.decode([OfflineCheckInMarker].self, from: data) else { return [] }
        return decoded
    }

    static func save(_ markers: [OfflineCheckInMarker], key: String) {
        guard let defaults = SharedAppGroup.defaults else { return }
        guard !markers.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? encoder.encode(markers) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Plain "I'm OK" taps from the phone's widget, Control Center control or Siri
/// that couldn't reach the server (offline, or the edge container restarting).
///
/// Before this they were simply lost: the intent returned a dialog nobody sees
/// from a widget button, nothing was saved, and the family was escalated for a
/// check-in the receiver believed they had made. The app moves these into its
/// own offline queue (which replays with `occurred_at`) on every sync.
///
/// Help requests are never queued here — like every other surface, an urgent
/// signal goes out live or the receiver is told it didn't send.
enum ExtensionCheckInQueue {
    static var pending: [OfflineCheckInMarker] {
        OfflineMarkerPolicy.prune(OfflineMarkerStore.load(key: OfflineMarkerStore.extensionKey))
    }

    static func enqueue(_ marker: OfflineCheckInMarker, calendar: Calendar = .current) {
        let current = OfflineMarkerStore.load(key: OfflineMarkerStore.extensionKey)
        OfflineMarkerStore.save(
            OfflineMarkerPolicy.enqueue(current, adding: marker, calendar: calendar),
            key: OfflineMarkerStore.extensionKey
        )
    }

    static func remove(_ marker: OfflineCheckInMarker) {
        let current = OfflineMarkerStore.load(key: OfflineMarkerStore.extensionKey)
        OfflineMarkerStore.save(current.filter { $0 != marker }, key: OfflineMarkerStore.extensionKey)
    }

    /// A live check-in settled today; earlier days stay queued.
    static func clearToday(calendar: Calendar = .current, now: Date = Date()) {
        let current = OfflineMarkerStore.load(key: OfflineMarkerStore.extensionKey)
        OfflineMarkerStore.save(
            current.filter { !calendar.isDate($0.at, inSameDayAs: now) },
            key: OfflineMarkerStore.extensionKey
        )
    }

    static func clear() {
        OfflineMarkerStore.save([], key: OfflineMarkerStore.extensionKey)
    }
}
