import WidgetKit
import Foundation

/// Timeline entry for the watch-face complication. Sourced from the watch's
/// local App Group snapshot (kept fresh by WatchConnectivity), so it renders
/// without a network round-trip.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let isSignedIn: Bool
    let hasCheckedInToday: Bool
    let lastCheckInAt: Date?

    static func from(_ state: SharedCheckInState?, date: Date = Date()) -> ComplicationEntry {
        ComplicationEntry(
            date: date,
            isSignedIn: state != nil,
            // Day-scoped so the complication flips back to "Check in" at a new
            // day even if the phone hasn't synced a fresh snapshot.
            hasCheckedInToday: state?.isCheckedIn(asOf: date) ?? false,
            lastCheckInAt: state?.lastCheckInAt
        )
    }

    static let sampleDue = ComplicationEntry(date: Date(), isSignedIn: true, hasCheckedInToday: false, lastCheckInAt: nil)
    static let sampleDone = ComplicationEntry(date: Date(), isSignedIn: true, hasCheckedInToday: true, lastCheckInAt: Date())
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { .sampleDue }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? .sampleDone : .from(SharedCheckInStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let state = SharedCheckInStore.load()
        let now = Date()
        var entries = [ComplicationEntry.from(state, date: now)]

        // Add an entry anchored at the next local midnight. `isCheckedIn(asOf:)`
        // is day-scoped, so recomputing at that instant flips "Checked in" back
        // to "Check in" exactly at the day boundary — even if WidgetKit doesn't
        // get a refresh slot for a while. The old single-entry timeline kept
        // showing a stale green "all set" past midnight until the ~15-min refresh
        // landed, so a receiver glancing at the wrist could skip a real check-in.
        let cal = Calendar.current
        if let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            entries.append(ComplicationEntry.from(state, date: nextMidnight))
        }

        // Still refresh roughly every 15 minutes; a completed check-in or a new
        // snapshot from the phone also triggers WidgetCenter reloads.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
