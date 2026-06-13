import SwiftUI
import SwiftData

@main
struct DailyOKApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var appState = AppState()
    @StateObject private var offlineService = OfflineCheckInService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Task { await AnalyticsService.shared.initialize() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(appState)
                .environmentObject(offlineService)
                .modelContainer(for: OfflineCheckIn.self)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    private func reRegisterPushToken() async {
        let status = await PushNotificationService.shared.checkPermissionStatus()
        if status == .authorized {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Verify URL scheme is one we expect
        guard url.scheme == "dailyok" || url.scheme == "https" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host else { return }

        switch host {
        case "invite", "dailyok.net":
            if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                // Validate token: must be hex string, bounded length
                guard token.count <= 500,
                      token.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else {
                    return // Silently reject invalid tokens
                }
                appState.pendingInviteToken = token
            }
        case "standdown":
            // From an escalation Live Activity "Stand down" button — stop the
            // escalation chain for this receiver (owner is authenticated here).
            if let r = components.queryItems?.first(where: { $0.name == "receiver" })?.value,
               let f = components.queryItems?.first(where: { $0.name == "family" })?.value,
               let receiverId = UUID(uuidString: r), let familyId = UUID(uuidString: f) {
                Task { try? await CheckInService.shared.cancelEscalation(receiverId: receiverId, familyId: familyId) }
            }
        default:
            break
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Sync pending offline check-ins when app becomes active
            Task { await offlineService.syncPendingCheckIns() }
            // Re-check auth state
            Task { await authViewModel.checkSession() }
            // Re-register push token on every foreground
            Task { await reRegisterPushToken() }
            Task { await AnalyticsService.shared.track(.appOpened) }
            // Validate server certificate pins
            Task {
                let valid = await CertificatePinningService.shared.validateServerCertificate()
                if !valid {
                    await AnalyticsService.shared.track(.certificatePinningFailure)
                }
            }
            // Biometric check on app resume
            Task { await authViewModel.checkBiometricOnResume() }
        case .background:
            Task { await AnalyticsService.shared.track(.appBackgrounded) }
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
