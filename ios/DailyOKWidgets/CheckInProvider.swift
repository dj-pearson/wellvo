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
    /// Whether the shared session tokens are currently available. False while
    /// biometric lock has withheld them (`SharedCheckInPublisher.withholdTokens`),
    /// even though the snapshot still says signed-in — so the surface can show a
    /// "locked" state instead of an actionable button that would just throw
    /// `notSignedIn` (US-IOS128).
    let tokensAvailable: Bool

    /// Signed-in per the snapshot but the tokens are withheld (biometric lock).
    var isLocked: Bool { isSignedIn && !tokensAvailable }

    static func from(_ state: SharedCheckInState?, date: Date = Date()) -> CheckInEntry {
        guard let state else {
            return CheckInEntry(
                date: date, isSignedIn: false, hasCheckedInToday: false,
                lastCheckInAt: nil, nextCheckInAt: nil, displayName: nil,
                tokensAvailable: false
            )
        }
        return CheckInEntry(
            date: date,
            isSignedIn: true,
            // Day-scoped so the widget flips back to "tap I'm OK" at a new day
            // even if the phone hasn't synced a fresh snapshot.
            hasCheckedInToday: state.isCheckedIn(asOf: date),
            lastCheckInAt: state.lastCheckInAt,
            nextCheckInAt: state.nextCheckInAt,
            displayName: state.displayName,
            tokensAvailable: SharedKeychain.loadTokens() != nil
        )
    }

    static let placeholder = CheckInEntry(
        date: Date(), isSignedIn: true, hasCheckedInToday: false,
        lastCheckInAt: nil, nextCheckInAt: nil, displayName: nil,
        tokensAvailable: true
    )

    static let checkedInSample = CheckInEntry(
        date: Date(), isSignedIn: true, hasCheckedInToday: true,
        lastCheckInAt: Date(), nextCheckInAt: nil, displayName: "Mom",
        tokensAvailable: true
    )
}

struct CheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckInEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CheckInEntry) -> Void) {
        completion(context.isPreview ? .checkedInSample : .from(SharedCheckInStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        let now = Date()
        let entry = CheckInEntry.from(SharedCheckInStore.load(), date: now)
        // Refresh around the next scheduled check-in AND at the next local
        // midnight (so a new day flips the widget back to "tap I'm OK" even if
        // the phone never syncs a fresh snapshot), but never less than 15
        // minutes out to respect WidgetKit's refresh budget.
        let soon = now.addingTimeInterval(15 * 60)
        let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        let candidates = [entry.nextCheckInAt, nextMidnight].compactMap { $0 }.filter { $0 > soon }
        let reload = candidates.min() ?? soon
        completion(Timeline(entries: [entry], policy: .after(reload)))
    }
}
