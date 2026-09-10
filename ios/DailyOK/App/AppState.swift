import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var pendingInviteToken: String?
    @Published var pendingAutoJoin: AutoJoinResult?
    @Published var currentUserRole: UserRole?
    @Published var selectedTab: AppTab = .dashboard
    @Published var isOnboarding: Bool = false
    @Published var showPairingCodeEntry: Bool = false

    /// Set when the launch/resume pin probe finds a genuine certificate
    /// mismatch (a device-trusted but un-pinned CA — possible MITM). Drives a
    /// blocking overlay; transient "couldn't evaluate" states never set this.
    @Published var secureConnectionFailed: Bool = false

    /// Covers the UI while the app is leaving the foreground, when the user
    /// relies on biometric lock.
    ///
    /// iOS captures the App Switcher snapshot during the `.inactive` window and
    /// keeps it on disk. Raising the biometric lock only on resume meant that
    /// snapshot was taken of the live dashboard, so anyone holding the phone
    /// could read a relative's status, location and care notes from the switcher
    /// card without ever passing Face ID — the one thing the lock is for.
    ///
    /// Deliberately separate from `AuthViewModel.biometricLocked`: this only
    /// obscures pixels. Raising the real lock here would re-enter the unlock
    /// prompt on every transient interruption, including the Face ID sheet's own.
    @Published var privacyCoverActive: Bool = false

    /// Result of a deep link that performed an ACTION rather than navigation —
    /// today, the escalation Live Activity's "Stand down" button.
    ///
    /// It used to only log. The owner taps Stand down on an overdue relative,
    /// the app opens, nothing visible happens, and if the call failed the
    /// escalation is still running while they believe they cancelled it. An
    /// action taken on someone's behalf has to report whether it happened.
    @Published var deepLinkOutcome: DeepLinkOutcome?

    struct DeepLinkOutcome: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        let isFailure: Bool
    }

    /// Non-essential haptics (selection, light, medium). Outcome haptics
    /// (success/warning/error) always fire so users don't miss a failure.
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "dailyok.haptics.enabled") }
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: "dailyok.haptics.enabled") as? Bool
        self.hapticsEnabled = stored ?? true
    }

    enum AppTab: Int, CaseIterable {
        case dashboard = 0
        case history = 1
        case family = 2
        case settings = 3
    }
}
