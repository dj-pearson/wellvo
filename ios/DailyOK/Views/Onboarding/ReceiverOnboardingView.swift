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
    // nil until the server provides the real time — never fabricate "8:00 AM"
    // (US-IOS112).
    @State private var checkinTimeDisplay: String?
    @State private var ownerName = "Your family"
    @State private var errorMessage: String?
    /// True when a token-based invite failed to redeem. Blocks the false "All set"
    /// success screen and surfaces Try Again / Cancel instead of stranding the
    /// user as a receiver of no family.
    @State private var joinFailed = false
    /// True once the receiver was asked for notification permission and denied it.
    @State private var notificationDenied = false

    /// Nil when using auto-join (phone match) flow.
    let inviteToken: String?

    var body: some View {
        ZStack {
            AmbientBackground(tone: currentStep == 2 ? .calm : .neutral)

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { step in
                        Capsule()
                            .fill(step <= currentStep ? DailyOKColor.green500 : Color.secondary.opacity(0.3))
                            .frame(width: step == currentStep ? 24 : 8, height: 8)
                            .animation(reduceMotion ? nil : DailyOKMotion.smoothSpring, value: currentStep)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassPill(style: .ultraThin)
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
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .transaction { t in if reduceMotion { t.animation = nil } }
                .animation(reduceMotion ? nil : DailyOKMotion.smoothSpring, value: currentStep)

                Spacer()
            }
            .padding(.horizontal, 32)
            .task { await processJoin() }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.45))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green400, DailyOKColor.green600],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }

            Text("Welcome to Daily OK")
                .font(.largeTitle)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(checkinTimeDisplay.map { "Every day at **\($0)**, we'll send you a notification." }
                 ?? "We'll remind you each day with a notification.")
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
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if joinFailed {
                // Invite couldn't be redeemed — don't advance to a fake success.
                VStack(spacing: 12) {
                    Button("Try Again") {
                        Task { await retryJoin() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green500)
                    .controlSize(.large)
                    .disabled(isProcessing)

                    Text("If this keeps happening, ask your family to send you a new invite.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Cancel") { cancelJoin() }
                        .foregroundStyle(.secondary)
                        .disabled(isProcessing)
                }
            } else {
                Button("Continue") {
                    if reduceMotion {
                        currentStep = 1
                    } else {
                        withAnimation(DailyOKMotion.smoothSpring) { currentStep = 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green500)
                .controlSize(.large)
                .disabled(isProcessing)
            }
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
    }

    // MARK: - Step 2: Notifications

    private var notificationStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.teal.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .blur(radius: 26)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green500, DailyOKColor.teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolEffect(.pulse)
            }

            Text("One Last Thing")
                .font(.title)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("We need to send you a notification each day so you can check in.\n\nWithout this, your family won't know you're OK.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            if notificationDenied {
                // The system won't re-prompt once denied — guide to Settings rather
                // than silently advancing to "All set" with no daily reminder.
                VStack(spacing: 16) {
                    Label("Notifications are turned off. You won't get your daily check-in reminder until you turn them on in Settings.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(DailyOKColor.gold)
                        .multilineTextAlignment(.center)
                        .labelStyle(.titleAndIcon)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green500)
                    .controlSize(.large)

                    Button("Continue anyway") { advanceToDone() }
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Allow Notifications") {
                    Task {
                        let granted = (try? await PushNotificationService.shared.requestPermission()) ?? false
                        if granted {
                            advanceToDone()
                        } else {
                            notificationDenied = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green500)
                .controlSize(.large)
            }
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
    }

    private func advanceToDone() {
        if reduceMotion {
            currentStep = 2
        } else {
            withAnimation(DailyOKMotion.smoothSpring) { currentStep = 2 }
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.55))
                    .frame(width: 150, height: 150)
                    .blur(radius: 32)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green400, DailyOKColor.green600],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.bounce, value: currentStep)
            }

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
            .tint(DailyOKColor.green500)
            .controlSize(.large)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
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
            errorMessage = nil
            joinFailed = false
        } catch {
            errorMessage = String(localized: "Could not join family. The invite may have expired.")
            joinFailed = true
        }
        isProcessing = false
    }

    private func retryJoin() async {
        guard let token = inviteToken else { return }
        await acceptInviteByToken(token)
    }

    /// Abandon a failed invite: clear the pending deep link and let ContentView
    /// re-resolve the user's role instead of stranding them on a dead screen.
    private func cancelJoin() {
        appState.pendingInviteToken = nil
        appState.pendingAutoJoin = nil
        appState.currentUserRole = nil
        appState.isOnboarding = false
    }

    private func formatCheckinTime(_ time: String) -> String {
        // `time` is the wire format "HH:mm" — parse with a fixed POSIX formatter,
        // then render locale-aware short time for display (US-IOS044).
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "HH:mm"
        guard let date = parser.date(from: time) else { return time }
        let display = DateFormatter()
        display.timeStyle = .short
        display.dateStyle = .none
        return display.string(from: date)
    }
}
