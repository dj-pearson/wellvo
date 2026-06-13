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
        let entry = OwnerStatusEntry(date: Date(), state: SharedOwnerStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}
