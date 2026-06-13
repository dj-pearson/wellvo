import SwiftUI
import WatchKit
import UserNotifications

/// Custom long-look UI for the check-in reminder on the watch. The action
/// buttons ("I'm OK ✓", etc.) are supplied by the CHECKIN_REQUEST category;
/// this just makes the top of the notification clear and reassuring.
final class CheckInNotificationController: WKUserNotificationHostingController<CheckInNotificationView> {
    private var title = "Daily OK"
    private var message = "Your family wants to hear from you."

    override var body: CheckInNotificationView {
        CheckInNotificationView(title: title, message: message)
    }

    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        // The server puts the family / sender context in the notification title;
        // fall back to the signed-in receiver's name from the shared snapshot.
        if !content.title.isEmpty {
            title = content.title
        } else if let name = SharedCheckInStore.load()?.displayName, !name.isEmpty {
            title = name
        }
        if !content.body.isEmpty { message = content.body }
    }
}

struct CheckInNotificationView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.wave.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.133, green: 0.773, blue: 0.369))
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            // The prominent "I'm OK ✓" affordance is rendered by the system from
            // the CHECKIN_REQUEST category actions directly below this content.
            Label("Tap “I'm OK” below", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color(red: 0.133, green: 0.773, blue: 0.369))
        }
        .padding()
    }
}
