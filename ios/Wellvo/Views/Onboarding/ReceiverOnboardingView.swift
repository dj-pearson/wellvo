import SwiftUI

/// Simplified onboarding flow for Receivers joining via invite link.
/// Intentionally minimal — matches PRD Section 7.2.
struct ReceiverOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var isProcessing = false
    @State private var checkinTimeDisplay = "8:00 AM"
    @State private var ownerName = "Your family"
    @State private var errorMessage: String?

    let inviteToken: String

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.green : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    notificationStep
                default:
                    doneStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer()
        }
        .padding(.horizontal, 32)
        .task { await acceptInvite() }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Welcome to Wellvo")
                .font(.largeTitle)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("Every day at **\(checkinTimeDisplay)**, we'll send you a notification.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("Just tap **\"I'm OK\"** and that's it.\nNo setup. No learning curve.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Continue") {
                withAnimation { currentStep = 1 }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(isProcessing)
        }
    }

    // MARK: - Step 2: Notifications

    private var notificationStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("One Last Thing")
                .font(.title)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("We need to send you a notification each day so you can check in.\n\nWithout this, your family won't know you're OK.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Button("Allow Notifications") {
                Task {
                    let granted = (try? await PushNotificationService.shared.requestPermission()) ?? false
                    if granted {
                        withAnimation { currentStep = 2 }
                    } else {
                        withAnimation { currentStep = 2 }
                        // Still proceed but they'll see the prompt in settings
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("\(ownerName) will be notified when you check in each day.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Button("Start Checking In") {
                appState.pendingInviteToken = nil
                appState.isOnboarding = false
                appState.currentUserRole = .receiver
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
    }

    // MARK: - Accept Invite

    private func acceptInvite() async {
        isProcessing = true
        do {
            try await FamilyService.shared.acceptInvite(token: inviteToken)
        } catch {
            errorMessage = "Could not join family. The invite may have expired."
        }
        isProcessing = false
    }
}
