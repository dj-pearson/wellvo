import SwiftUI

/// First screen for a signed-in user who belongs to no family yet.
///
/// Before this existed, such a user fell straight through to the owner's tabs:
/// an empty dashboard whose "Get Started" needed an owner role they did not
/// have (owner setup was unreachable), and — for a receiver whose invite had
/// not matched — owner screens they should never see. Setup has exactly two
/// starts, so ask:
///   * "Set up check-ins for someone" → owner onboarding (create the family,
///     invite the first receiver).
///   * "I was invited"                → enter the setup code from the text.
struct GetStartedChoiceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showSignOutConfirm = false

    var body: some View {
        ZStack {
            AmbientBackground(tone: .calm)

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Welcome to Daily OK")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("How will you use it?")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let blocked = appState.autoJoinBlockedMessage {
                    // Their number matched an invite, but the family's plan is
                    // full. Say so, rather than let them pick "Set up check-ins
                    // for someone" and become the owner of an empty family.
                    VStack(alignment: .leading, spacing: 10) {
                        Label("You've been invited, but can't join yet", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.headline)
                        Text(blocked)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("We've let them know. Try again once they've made room.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            appState.autoJoinBlockedMessage = nil
                            appState.roleResolution = .resolving
                            appState.roleRefreshRequest += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DailyOKColor.green700)
                    }
                    .padding()
                    .glassCard(style: .thin, radius: DailyOKGlass.radiusMedium, elevation: DailyOKElevation.level2)
                    .padding(.horizontal, 24)
                    .accessibilityElement(children: .contain)
                }

                VStack(spacing: 12) {
                    choiceButton(
                        title: "I was invited",
                        subtitle: "Someone sent me a text with a 6-digit setup code",
                        icon: "envelope.open.fill"
                    ) {
                        appState.showPairingCodeEntry = true
                    }

                    choiceButton(
                        title: "Set up check-ins for someone",
                        subtitle: "You'll be the organizer who gets alerts about a parent, child or friend",
                        icon: "person.2.fill"
                    ) {
                        appState.isOnboarding = true
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button("Sign out") { showSignOutConfirm = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .confirmationDialog("Sign out of Daily OK?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func choiceButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(DailyOKColor.green600)
                    .frame(width: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(minHeight: 72)
            .glassCard(style: .thin, radius: DailyOKGlass.radiusMedium, elevation: DailyOKElevation.level2)
        }
        .buttonStyle(.pressable)
    }
}
