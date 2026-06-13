import SwiftUI
import WatchKit
import UserNotifications

/// Custom long-look UI for the check-in reminder on the watch. The action
/// buttons ("I'm OK ✓", etc.) are supplied by the CHECKIN_REQUEST category;
/// this just makes the top of the notification clear and reassuring.
final class CheckInNotificationController: WKUserNotificationHostingController<CheckInNotificationView> {
    private var message = "Your family wants to hear from you."

    override var body: CheckInNotificationView {
        CheckInNotificationView(message: message)
    }

    override func didReceive(_ notification: UNNotification) {
        let body = notification.request.content.body
        if !body.isEmpty { message = body }
    }
}

struct CheckInNotificationView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.wave.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.133, green: 0.773, blue: 0.369))
            Text("Daily OK")
                .font(.headline)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
