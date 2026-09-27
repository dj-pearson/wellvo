import Foundation
import WidgetKit

/// Publishes the owner's dashboard status into the shared App Group for the
/// owner status widget. Called by the dashboard after it loads/refreshes.
enum SharedOwnerPublisher {
    static func publish(_ cards: [ReceiverStatusCard]) {
        let now = Date()
        let receivers = cards.map { card in
            SharedOwnerReceiver(
                id: card.id.uuidString,
                name: card.name,
                status: statusString(card.status),
                lastCheckInAt: card.lastCheckIn,
                statusDate: now,
                // What the dashboard shows and the widget used to drop: a miss
                // the owner already handled, which kind of help, whose clock
                // "today" runs on, and who is on it.
                stoodDown: card.stoodDown ? true : nil,
                helpKind: card.helpKind.map(helpKindString),
                timeZoneId: card.timezone,
                claimedByName: card.claimedByName
            )
        }
        SharedOwnerStore.save(SharedOwnerState(receivers: receivers, updatedAt: now))
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        SharedOwnerStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func helpKindString(_ kind: HelpKind) -> String {
        switch kind {
        case .needHelp: return "need_help"
        case .callMe: return "call_me"
        case .sos: return "sos"
        }
    }

    private static func statusString(_ status: ReceiverCheckInStatus) -> String {
        switch status {
        case .checkedIn: return "checked_in"
        case .pending: return "pending"
        case .missed: return "missed"
        case .noData: return "no_data"
        case .needsHelp: return "needs_help"
        case .upcoming: return "upcoming"
        }
    }
}
