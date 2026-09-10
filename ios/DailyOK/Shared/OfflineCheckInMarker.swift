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
}
