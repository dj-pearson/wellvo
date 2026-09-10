import WidgetKit
import Foundation

struct OwnerStatusEntry: TimelineEntry {
    let date: Date
    let state: SharedOwnerState?

    static let sample = OwnerStatusEntry(
        date: Date(),
        state: SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Mom", status: "checked_in", lastCheckInAt: Date()),
                SharedOwnerReceiver(id: "2", name: "Dad", status: "pending", lastCheckInAt: nil),
            ],
            updatedAt: Date()
        )
    )
}

struct OwnerStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> OwnerStatusEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (OwnerStatusEntry) -> Void) {
        completion(context.isPreview ? .sample : OwnerStatusEntry(date: Date(), state: SharedOwnerStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OwnerStatusEntry>) -> Void) {
        let now = Date()
        let state = SharedOwnerStore.load()

        // Two entries, so the day flip is rendered AT midnight rather than
        // whenever the next reload happens to land. The views read status as of
        // the entry's date, so the second entry shows an un-answered new day
        // even though the snapshot behind it has not changed — which it will
        // not, until the owner next opens the app.
        var entries = [OwnerStatusEntry(date: now, state: state)]
        if let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            entries.append(OwnerStatusEntry(date: midnight, state: state))
        }

        // Refresh sooner while a receiver is missed/pending so the owner widget
        // doesn't lag an active escalation by up to 15 minutes; back off to 15
        // minutes once everyone's checked in (US-IOS107). Evaluated day-scoped,
        // so a stale "checked in" no longer reads as "nothing to watch".
        let needsAttention = state?.receivers.contains {
            let status = $0.status(asOf: now)
            return status == "missed" || status == "pending"
        } ?? false
        let refreshIn: TimeInterval = needsAttention ? 5 * 60 : 15 * 60
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshIn))))
    }
}
