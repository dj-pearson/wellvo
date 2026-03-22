import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                LaunchScreenView()
            case .unauthenticated:
                AuthView()
            case .authenticated:
                if let inviteToken = appState.pendingInviteToken {
                    ReceiverOnboardingView(inviteToken: inviteToken)
                } else if appState.pendingAutoJoin != nil {
                    ReceiverOnboardingView(inviteToken: nil)
                } else if appState.isOnboarding {
                    OnboardingView()
                } else if appState.currentUserRole == .receiver {
                    ReceiverHomeView()
                } else if appState.currentUserRole == .viewer {
                    ViewerTabView()
                } else {
                    OwnerTabView()
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut, value: authViewModel.authState)
        .task(id: authViewModel.authState) {
            // After authentication, check for phone-based auto-join
            guard authViewModel.authState == .authenticated,
                  appState.pendingInviteToken == nil,
                  appState.pendingAutoJoin == nil,
                  appState.currentUserRole == nil else { return }

            do {
                if let result = try await FamilyService.shared.checkAutoJoin() {
                    appState.pendingAutoJoin = result
                }
            } catch {
                // Auto-join is best-effort; don't block the user
            }
        }
    }
}

struct LaunchScreenView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var heartSize: CGFloat = 80

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: heartSize))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Wellvo heart icon")
                Text("Wellvo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityLabel("Wellvo")
                ProgressView()
                    .accessibilityLabel("Loading")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Wellvo is loading")
        }
    }
}
