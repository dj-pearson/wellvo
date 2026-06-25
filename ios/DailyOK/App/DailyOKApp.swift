import SwiftUI
import SwiftData
import os

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
                // Don't let an invite link hijack an already-onboarded member and
                // demote them into the receiver onboarding flow. If we already know
                // their role, ignore the token. (ContentView also re-resolves role
                // and clears a stale token on cold-start from a link.)
                guard appState.currentUserRole == nil else { return }
                appState.pendingInviteToken = token
            }
        case "standdown":
            // From an escalation Live Activity "Stand down" button. The custom
            // URL scheme is public, so anything could invoke this — require an
            // authenticated session before acting, and rely on the
            // cancel-escalation edge function (which enforces caller == family
            // owner) to reject anyone who isn't the owner of this family.
            if let r = components.queryItems?.first(where: { $0.name == "receiver" })?.value,
               let f = components.queryItems?.first(where: { $0.name == "family" })?.value,
               let receiverId = UUID(uuidString: r), let familyId = UUID(uuidString: f) {
                Task {
                    guard (try? await SupabaseService.shared.client.auth.session) != nil else {
                        Log.general.error("Ignoring standdown deep link: no authenticated session")
                        return
                    }
                    do {
                        try await CheckInService.shared.cancelEscalation(receiverId: receiverId, familyId: familyId)
                        // End the Live Activity immediately on success so the
                        // owner isn't left with a running overdue timer for a
                        // resolved escalation (US-IOS081).
                        await MainActor.run {
                            EscalationActivityManager.end(receiverId: receiverId.uuidString)
                        }
                    } catch {
                        Log.general.error("Standdown deep link failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        default:
            break
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Run foreground work as a single ordered task instead of six
            // concurrent Tasks all competing for the first connection on resume.
            // Auth-critical work first, then sync/push, then best-effort work.
            Task {
                // Session first so downstream work uses a valid token; biometric
                // gate immediately after.
                await authViewModel.checkSession()
                await authViewModel.checkBiometricOnResume()
                // Sync queued check-ins and refresh the push token.
                await offlineService.syncPendingCheckIns()
                await reRegisterPushToken()
                // Re-anchor last_seen on foreground — the heartbeat timer is
                // suspended while backgrounded (US-IOS098).
                HeartbeatService.shared.appBecameActive()
                // Non-urgent / best-effort work last.
                await AnalyticsService.shared.track(.appOpened)
                // A genuine pin MISMATCH (device-trusted but un-pinned CA) is
                // treated as a possible MITM: surface a blocking state instead of
                // merely logging and proceeding. A transient "couldn't evaluate"
                // (captive portal, offline) is ignored — inline enforcement on
                // each real request still fails those closed if they're hostile.
                switch await CertificatePinningService.shared.validate() {
                case .mismatch:
                    await AnalyticsService.shared.track(.certificatePinningFailure)
                    await MainActor.run { appState.secureConnectionFailed = true }
                case .pinned:
                    await MainActor.run { appState.secureConnectionFailed = false }
                case .unevaluable:
                    break
                }
            }
        case .background:
            // Stop the foreground heartbeat timer when backgrounded (it can't
            // fire while suspended anyway); checkSession restarts it on resume.
            HeartbeatService.shared.stop()
            Task {
                await AnalyticsService.shared.track(.appBackgrounded)
                // If the user relies on biometric lock, pull the mirrored session
                // out of reach of widgets/Siri/watch the moment we background, so
                // a found/handed-off phone can't be used to check in before the
                // owner passes Face ID on the next resume.
                if await BiometricService.shared.isEnabled {
                    SharedCheckInPublisher.withholdTokens()
                }
            }
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
