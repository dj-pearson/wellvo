import WidgetKit
import Foundation

/// Timeline entry for the receiver check-in widget. Sourced entirely from the
/// shared App Group snapshot so it renders without a network round-trip.
struct CheckInEntry: TimelineEntry {
    let date: Date
    let isSignedIn: Bool
    let hasCheckedInToday: Bool
    let lastCheckInAt: Date?
    let nextCheckInAt: Date?
    let displayName: String?

    static func from(_ state: SharedCheckInState?, date: Date = Date()) -> CheckInEntry {
        guard let state else {
            return CheckInEntry(
                date: date, isSignedIn: false, hasCheckedInToday: false,
                lastCheckInAt: nil, nextCheckInAt: nil, displayName: nil
            )
        }
        return CheckInEntry(
            date: date,
            isSignedIn: true,
            hasCheckedInToday: state.hasCheckedInToday,
            lastCheckInAt: state.lastCheckInAt,
            nextCheckInAt: state.nextCheckInAt,
            displayName: state.displayName
        )
    }

    static let placeholder = CheckInEntry(
        date: Date(), isSignedIn: true, hasCheckedInToday: false,
        lastCheckInAt: nil, nextCheckInAt: nil, displayName: nil
    )

    static let checkedInSample = CheckInEntry(
        date: Date(), isSignedIn: true, hasCheckedInToday: true,
        lastCheckInAt: Date(), nextCheckInAt: nil, displayName: "Mom"
    )
}

struct CheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckInEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CheckInEntry) -> Void) {
        completion(context.isPreview ? .checkedInSample : .from(SharedCheckInStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        let entry = CheckInEntry.from(SharedCheckInStore.load())
        // Refresh around the next scheduled check-in (so a new day flips the
        // widget back to "tap I'm OK"), but never less than 15 minutes out.
        let soon = Date().addingTimeInterval(15 * 60)
        let reload = max(entry.nextCheckInAt ?? soon, soon)
        completion(Timeline(entries: [entry], policy: .after(reload)))
    }
}
