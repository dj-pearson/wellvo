import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var pendingInviteToken: String?
    @Published var pendingAutoJoin: AutoJoinResult?
    @Published var currentUserRole: UserRole?
    @Published var selectedTab: AppTab = .dashboard
    @Published var isOnboarding: Bool = false

    enum AppTab: Int, CaseIterable {
        case dashboard = 0
        case history = 1
        case family = 2
        case settings = 3
    }
}
