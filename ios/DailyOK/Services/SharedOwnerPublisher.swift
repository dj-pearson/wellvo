import Foundation
import WidgetKit

/// Publishes the owner's dashboard status into the shared App Group for the
/// owner status widget. Called by the dashboard after it loads/refreshes.
enum SharedOwnerPublisher {
    static func publish(_ cards: [ReceiverStatusCard]) {
        let receivers = cards.map { card in
            SharedOwnerReceiver(
                id: card.id.uuidString,
                name: card.name,
                status: statusString(card.status),
                lastCheckInAt: card.lastCheckIn
            )
        }
        SharedOwnerStore.save(SharedOwnerState(receivers: receivers, updatedAt: Date()))
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        SharedOwnerStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func statusString(_ status: ReceiverCheckInStatus) -> String {
        switch status {
        case .checkedIn: return "checked_in"
        case .pending: return "pending"
        case .missed: return "missed"
        case .noData: return "no_data"
        }
    }
}
