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
        //
        // One entry per distinct midnight: each receiver's day turns over in
        // their own zone (a parent in another state rolls over hours apart).
        var entries = [OwnerStatusEntry(date: now, state: state)]
        let calendars = [Calendar.current] + (state?.receivers.map(\.receiverCalendar) ?? [])
        let midnights = Set(calendars.compactMap {
            $0.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
        })
        for midnight in midnights.sorted().prefix(4) {
            entries.append(OwnerStatusEntry(date: midnight, state: state))
        }

        // The snapshot changes only when the app writes it, and the app reloads
        // every timeline when it does, so polling it every 5 minutes re-read
        // identical bytes and spent WidgetKit's daily budget — the budget the
        // reloads that matter draw on. 15 minutes while someone needs attention
        // (keeps the "Updated … ago" footnote honest), 30 otherwise.
        let needsAttention = state?.needsAttention(asOf: now) ?? false
        let refreshIn: TimeInterval = needsAttention ? 15 * 60 : 30 * 60
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshIn))))
    }
}
