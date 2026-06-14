import SwiftUI
import UserNotifications

/// A non-intrusive banner shown when notification permission is denied.
/// Dismissable for 7 days. Links to iOS Settings.
struct NotificationPermissionBanner: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    // Start as `.notDetermined`, NOT `.authorized`. The previous default meant a
    // receiver who denied notifications was never shown the banner unless a host
    // happened to call `checkPermission()` — defeating the safety net for the
    // most at-risk user. The banner now drives its own permission check below,
    // so it works regardless of where it's placed.
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var isDismissed = false

    private let dismissKey = "notificationBannerDismissedAt"

    var body: some View {
        // A `Group` adds no layout footprint when its content is empty (unlike a
        // clear placeholder), yet the `.task`/`.onChange` stay attached so the
        // banner detects a denied state even while currently hidden.
        Group {
            if shouldShow {
                bannerContent
            }
        }
        .task { await checkPermission() }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-check on foreground — the user may have toggled notifications in
            // iOS Settings while the app was backgrounded.
            if newPhase == .active {
                Task { await checkPermission() }
            }
        }
    }

    private var bannerContent: some View {
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
                .accessibilityHint("Opens iOS Settings to enable notifications for Daily OK")
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Notifications are disabled. Enable them in Settings to receive check-in alerts.")
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
        if reduceMotion {
            isDismissed = true
        } else {
            withAnimation { isDismissed = true }
        }
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
