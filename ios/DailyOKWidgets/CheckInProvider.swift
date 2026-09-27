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
    /// Today's help request ("need_help" / "call_me" / "sos"), if any. Shown as
    /// "Help requested", never as "You're all set".
    var helpKind: String? = nil
    var helpAt: Date? = nil
    /// A tap saved on this phone that hasn't reached the server yet.
    var pendingSend: Bool = false
    /// A refusal from the last tap ("Didn't send — open Daily OK").
    var failureMessage: String? = nil
    var ownerName: String? = nil
    /// The family asked again after the last check-in (the NSE recorded a
    /// newer check-in request).
    var askedAgain: Bool = false
    /// The receiver's zone, for times and the midnight flip.
    var timeZone: TimeZone = .current

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
        let done = state.isCheckedIn(asOf: date)
        let cal = state.receiverCalendar
        let askedAgain = !done && state.hasCheckedInToday
            && state.lastCheckInAt.map { cal.isDate($0, inSameDayAs: date) } == true
        return CheckInEntry(
            date: date,
            isSignedIn: true,
            // Day-scoped so the widget flips back to "tap I'm OK" at a new day
            // even if the phone hasn't synced a fresh snapshot.
            hasCheckedInToday: done,
            lastCheckInAt: state.lastCheckInAt,
            nextCheckInAt: state.nextCheckInAt,
            displayName: state.displayName,
            tokensAvailable: SharedKeychain.loadTokens() != nil,
            helpKind: state.helpRequested(asOf: date),
            helpAt: state.helpAt,
            // Not gated on `done`: the app marks a tap it only QUEUED as done
            // (so nothing re-prompts) and flags it pending; that must read
            // "Saved", never "You're all set".
            pendingSend: state.hasPendingSend(asOf: date),
            failureMessage: done ? nil : state.failureMessage(asOf: date),
            ownerName: state.ownerName,
            askedAgain: askedAgain,
            timeZone: cal.timeZone
        )
    }

    /// "8:15 AM" in the receiver's zone.
    func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
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
        let state = SharedCheckInStore.load()
        let entry = CheckInEntry.from(state, date: now)
        // Refresh around the next scheduled check-in AND at the next midnight
        // in the receiver's zone (so a new day flips the widget back to "tap
        // I'm OK" even if the phone never syncs a fresh snapshot), but never
        // less than 15 minutes out to respect WidgetKit's refresh budget. The
        // midnight flip is also its own entry, so it lands on time rather than
        // whenever the reload does.
        let soon = now.addingTimeInterval(15 * 60)
        let calendar = state?.receiverCalendar ?? Calendar.current
        let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        var entries = [entry]
        if let nextMidnight {
            entries.append(CheckInEntry.from(state, date: nextMidnight))
        }
        let candidates = [entry.nextCheckInAt, nextMidnight].compactMap { $0 }.filter { $0 > soon }
        let reload = candidates.min() ?? soon
        completion(Timeline(entries: entries, policy: .after(reload)))
    }
}
