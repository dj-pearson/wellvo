import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState

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
                } else if appState.isOnboarding {
                    OnboardingView()
                } else if appState.currentUserRole == .receiver {
                    ReceiverHomeView()
                } else {
                    OwnerTabView()
                }
            }
        }
        .animation(.easeInOut, value: authViewModel.authState)
    }
}

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                Text("Wellvo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                ProgressView()
            }
        }
    }
}
