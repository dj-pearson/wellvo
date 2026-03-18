import SwiftUI
import UserNotifications

/// A non-intrusive banner shown when notification permission is denied.
/// Dismissable for 7 days. Links to iOS Settings.
struct NotificationPermissionBanner: View {
    @State private var permissionStatus: UNAuthorizationStatus = .authorized
    @State private var isDismissed = false

    private let dismissKey = "notificationBannerDismissedAt"

    var body: some View {
        if shouldShow {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Disabled")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Enable notifications to receive check-in reminders and escalation alerts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss notification banner")
                }

                Button {
                    openSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open Settings")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityLabel("Open notification settings")
                .accessibilityHint("Opens iOS Settings to enable notifications for Wellvo")
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Notifications are disabled. Enable them in Settings to receive check-in alerts.")
        }
    }

    private var shouldShow: Bool {
        guard permissionStatus == .denied, !isDismissed else { return false }

        // Check if dismissed within the last 7 days
        if let dismissedAt = UserDefaults.standard.object(forKey: dismissKey) as? Date {
            let daysSinceDismiss = Calendar.current.dateComponents([.day], from: dismissedAt, to: Date()).day ?? 0
            if daysSinceDismiss < 7 {
                return false
            }
        }

        return true
    }

    private func dismiss() {
        UserDefaults.standard.set(Date(), forKey: dismissKey)
        withAnimation { isDismissed = true }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            permissionStatus = settings.authorizationStatus
        }
    }
}
