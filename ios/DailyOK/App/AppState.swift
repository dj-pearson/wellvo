import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var pendingInviteToken: String?
    @Published var pendingAutoJoin: AutoJoinResult?
    @Published var currentUserRole: UserRole?
    @Published var selectedTab: AppTab = .dashboard
    @Published var isOnboarding: Bool = false
    @Published var showPairingCodeEntry: Bool = false

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
