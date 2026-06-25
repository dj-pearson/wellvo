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
        let state = SharedOwnerStore.load()
        let entry = OwnerStatusEntry(date: Date(), state: state)
        // Refresh sooner while a receiver is missed/pending so the owner widget
        // doesn't lag an active escalation by up to 15 minutes; back off to 15
        // minutes once everyone's checked in (US-IOS107).
        let needsAttention = state?.receivers.contains { $0.status == "missed" || $0.status == "pending" } ?? false
        let refreshIn: TimeInterval = needsAttention ? 5 * 60 : 15 * 60
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(refreshIn))))
    }
}
