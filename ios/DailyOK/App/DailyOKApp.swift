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
    /// The app lock asks for Face ID on a launch or a return from the
    /// background, never on an `.inactive` → `.active` bounce. The Face ID sheet
    /// itself (and Control Center, Notification Center, an incoming call)
    /// bounces the scene through `.inactive`; locking again on that return
    /// re-prompted after every successful unlock, forever. Latent until
    /// Settings gained its "Require Face ID" toggle.
    @State private var biometricCheckDue = true

    init() {
        // Before anything reads a persisted session. Stored-property
        // initializers (including AuthViewModel's, which starts a session check)
        // have already run, but their Tasks cannot interleave with this
        // synchronous main-thread init, so this still lands first (US-IOS143).
        KeychainService.purgeIfFreshInstall()
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

    /// The invite token from a link — the last path segment of
    /// `/invite/<token>`, else the `token` query item — if it is a plausible
    /// hex token. Anything else is ignored.
    nonisolated static func inviteToken(from components: URLComponents) -> String? {
        let segments = components.path.split(separator: "/").map(String.init)
        let candidate: String?
        if segments.count == 2, segments[0] == "invite" {
            candidate = segments[1]
        } else {
            candidate = components.queryItems?.first(where: { $0.name == "token" })?.value
        }
        guard let token = candidate,
              (16...500).contains(token.count),
              token.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else {
            return nil
        }
        return token
    }

    private func handleDeepLink(_ url: URL) {
        // Verify URL scheme is one we expect
        guard url.scheme == "dailyok" || url.scheme == "https" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host else { return }

        switch host {
        case "invite", "dailyok.net", "www.dailyok.net":
            // dailyok://invite?token=…                    (website "Open Daily OK")
            // https://dailyok.net/invite/<token>?code=…   (the invite text)
            // https://dailyok.net/invite?token=…          (older invite texts)
            // Other dailyok.net paths are not ours to handle.
            if host != "invite" {
                let path = components.path
                guard path == "/invite" || path == "/invite/" || path.hasPrefix("/invite/") else { return }
            }
            guard let token = Self.inviteToken(from: components) else { return }
            // Don't let an invite link hijack an already-onboarded member and
            // demote them into the receiver onboarding flow. If we already know
            // their role, ignore the token. (ContentView also re-resolves role
            // and clears a stale token on cold-start from a link.)
            guard appState.currentUserRole == nil else { return }
            appState.pendingInviteToken = token
        case "dashboard":
            // Owner status widget tap (dailyok://dashboard) — jump to the
            // dashboard tab (US-IOS091).
            appState.selectedTab = .dashboard
        case "checkin":
            // Check-in widget / Control Center control tap (dailyok://checkin).
            // Opening the app is the action: a signed-in receiver lands on their
            // check-in home, and a not-signed-in user is routed to AuthView by
            // ContentView (authState == .unauthenticated). Handled explicitly so
            // it no longer falls through to `default` (which silently reopened
            // the last screen — US-IOS091). For a signed-in owner, make sure a
            // stale pairing-entry sheet isn't blocking the dashboard.
            if authViewModel.currentUser != nil {
                appState.showPairingCodeEntry = false
            }
        case "standdown":
            // From an escalation Live Activity "Stand down" button. The custom
            // URL scheme is public, so anything could invoke this — a crafted
            // link texted to the owner would pass the server's owner check,
            // because the owner's own phone is the caller. So this never
            // cancels anything by itself: it opens the dashboard, which asks
            // "Stop alerts for <name>?" — the same confirmation as the card —
            // and only for a receiver who is escalating in the owner's family.
            guard let r = components.queryItems?.first(where: { $0.name == "receiver" })?.value,
                  let f = components.queryItems?.first(where: { $0.name == "family" })?.value,
                  let receiverId = UUID(uuidString: r), let familyId = UUID(uuidString: f) else {
                Log.general.error("Ignoring standdown deep link: malformed receiver/family parameters")
                appState.selectedTab = .dashboard
                reportDeepLink(
                    title: "Couldn't open that alert",
                    message: "That link was incomplete. Alerts are still running — stand down from the receiver's card if you've reached them.",
                    isFailure: true
                )
                return
            }
            appState.selectedTab = .dashboard
            appState.pendingStandDown = AppState.PendingStandDown(receiverId: receiverId, familyId: familyId)
        default:
            break
        }
    }

    /// Surface the result of an action taken from a deep link, with the outcome
    /// haptic that always fires (AppState.hapticsEnabled gates only the
    /// non-essential ones, precisely so a failure is never silent).
    private func reportDeepLink(title: String, message: String, isFailure: Bool) {
        Task { @MainActor in
            appState.deepLinkOutcome = AppState.DeepLinkOutcome(
                title: title,
                message: message,
                isFailure: isFailure
            )
            if isFailure { DailyOKHaptics.error() } else { DailyOKHaptics.success() }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        // Drop / raise the snapshot cover first, before any awaiting work: the
        // App Switcher snapshot is taken during `.inactive` and will not wait.
        switch phase {
        case .active:
            appState.privacyCoverActive = false
        case .inactive, .background:
            appState.privacyCoverActive =
                authViewModel.authState == .authenticated && BiometricService.isEnabledPreference
        @unknown default:
            break
        }

        switch phase {
        case .active:
            let checkBiometric = biometricCheckDue
            biometricCheckDue = false
            // Run foreground work as a single ordered task instead of six
            // concurrent Tasks all competing for the first connection on resume.
            // Auth-critical work first, then sync/push, then best-effort work.
            Task {
                // Session first so downstream work uses a valid token; biometric
                // gate immediately after.
                await authViewModel.checkSession()
                if checkBiometric { await authViewModel.checkBiometricOnResume() }
                // Sync queued check-ins and refresh the push token.
                await offlineService.syncPendingCheckIns()
                await reRegisterPushToken()
                // Re-anchor last_seen on foreground — the heartbeat timer is
                // suspended while backgrounded (US-IOS098).
                HeartbeatService.shared.appBecameActive()
                // Reconcile any verified-but-unsynced subscription to the backend
                // once per launch (reinstall / interrupted purchase) — US-IOS095.
                // The latch only closes on success, and this registers a
                // connectivity-restored retry, so a launch that happens before the
                // network is up no longer leaves the user un-provisioned for the
                // rest of the process lifetime (US-IOS139).
                SubscriptionService.shared.startRetryingWhenOnline()
                await SubscriptionService.shared.reconcileEntitlementsToBackendOnce()
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
            biometricCheckDue = true
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
