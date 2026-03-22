import SwiftUI

/// Simplified onboarding flow for Receivers.
/// Supports two paths:
/// 1. Token-based (deep link) — accepts invite via token
/// 2. Auto-join (phone match) — invite already accepted by auto-join endpoint
struct ReceiverOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var currentStep = 0
    @State private var isProcessing = false
    @State private var checkinTimeDisplay = "8:00 AM"
    @State private var ownerName = "Your family"
    @State private var errorMessage: String?

    /// Nil when using auto-join (phone match) flow.
    let inviteToken: String?

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(currentStep + 1) of 3")

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
            .transaction { t in if reduceMotion { t.animation = nil } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentStep)

            Spacer()
        }
        .padding(.horizontal, 32)
        .task { await processJoin() }
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
                if reduceMotion {
                    currentStep = 1
                } else {
                    withAnimation { currentStep = 1 }
                }
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
                    let _ = (try? await PushNotificationService.shared.requestPermission()) ?? false
                    if reduceMotion {
                        currentStep = 2
                    } else {
                        withAnimation { currentStep = 2 }
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
                appState.pendingAutoJoin = nil
                appState.isOnboarding = false
                appState.currentUserRole = .receiver
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
    }

    // MARK: - Join Logic

    private func processJoin() async {
        if let token = inviteToken {
            // Token-based flow (deep link)
            await acceptInviteByToken(token)
        } else if let autoJoin = appState.pendingAutoJoin {
            // Auto-join flow — invite already accepted server-side
            if let time = autoJoin.checkinTime {
                checkinTimeDisplay = formatCheckinTime(time)
            }
        }
    }

    private func acceptInviteByToken(_ token: String) async {
        isProcessing = true
        do {
            try await FamilyService.shared.acceptInvite(token: token)
        } catch {
            errorMessage = "Could not join family. The invite may have expired."
        }
        isProcessing = false
    }

    private func formatCheckinTime(_ time: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let date = formatter.date(from: time) else { return time }
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
