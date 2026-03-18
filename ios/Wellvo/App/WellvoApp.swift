import SwiftUI
import SwiftData

@main
struct WellvoApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var appState = AppState()
    @StateObject private var offlineService = OfflineCheckInService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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

    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host else { return }

        switch host {
        case "invite":
            if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                appState.pendingInviteToken = token
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
        case .background:
            // App is backgrounded — no action needed, NWPathMonitor handles reconnect
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
