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
        let entry = ComplicationEntry.from(SharedCheckInStore.load())
        // Refresh roughly every 15 minutes; a completed check-in or a new
        // snapshot from the phone also triggers WidgetCenter reloads.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}
