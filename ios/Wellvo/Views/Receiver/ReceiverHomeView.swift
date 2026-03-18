import SwiftUI

struct ReceiverHomeView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @State private var buttonScale: CGFloat = 1.0
    @State private var isPulsing = false
    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0

    private let hapticSuccess = UINotificationFeedbackGenerator()
    private let hapticImpact = UIImpactFeedbackGenerator(style: .medium)

    @State private var notificationBanner = NotificationPermissionBanner()

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                // Notification permission banner
                NotificationPermissionBanner()
                    .padding(.horizontal)
                    .task { await notificationBanner.checkPermission() }

                // Offline banner
                if viewModel.isOffline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                        Text(viewModel.pendingOfflineCount > 0
                             ? "Offline — \(viewModel.pendingOfflineCount) check-in(s) will sync when reconnected"
                             : "You're offline")
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange, in: Capsule())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityLabel(viewModel.pendingOfflineCount > 0
                        ? "Offline. \(viewModel.pendingOfflineCount) check-ins pending sync."
                        : "You are offline")
                }

                Spacer()

                if viewModel.hasCheckedInToday {
                    checkedInState
                } else {
                    checkInButton
                }

                Spacer()

                // Mood selector overlay
                if viewModel.showMoodSelector {
                    moodSelector
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()
        }
        .task { await viewModel.loadStatus() }
    }

    // MARK: - Check-In Button (Not Yet Checked In)

    private var checkInButton: some View {
        VStack(spacing: 24) {
            Text("Good morning!")
                .font(.title2)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

            Button {
                hapticImpact.impactOccurred()
                Task {
                    await viewModel.performCheckIn()
                    if viewModel.hasCheckedInToday {
                        hapticSuccess.notificationOccurred(.success)
                        animateCheckmark()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.8, blue: 0.443)) // #2ECC71
                        .frame(width: 200, height: 200)
                        .shadow(color: .green.opacity(0.4), radius: isPulsing ? 20 : 10)
                        .scaleEffect(buttonScale)

                    if showCheckmark {
                        // Animated checkmark transition
                        Image(systemName: "checkmark")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(checkmarkScale)
                            .opacity(checkmarkOpacity)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)

                            Text("I'm OK")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .disabled(viewModel.isCheckingIn)
            .accessibilityLabel("Tap to check in and let your family know you're okay")
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                    buttonScale = 1.05
                }
            }

            if viewModel.isCheckingIn {
                ProgressView("Checking in...")
                    .font(.body)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text("Tap to let your family know you're OK")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }

    // MARK: - Checked In State

    private var checkedInState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 200, height: 200)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: viewModel.hasCheckedInToday)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Checked in successfully")

            Text("Your family knows you're OK")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

            if let checkIn = viewModel.lastCheckIn {
                Text("Checked in at \(checkIn.checkedInAt.formatted(date: .omitted, time: .shortened))")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
        }
    }

    // MARK: - Mood Selector

    private var moodSelector: some View {
        VStack(spacing: 16) {
            Text("How are you feeling?")
                .font(.headline)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            HStack(spacing: 24) {
                MoodButton(mood: .happy, emoji: "😊", label: "Good") {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitMood(.happy) }
                }

                MoodButton(mood: .neutral, emoji: "😐", label: "Okay") {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitMood(.neutral) }
                }

                MoodButton(mood: .tired, emoji: "😴", label: "Tired") {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitMood(.tired) }
                }
            }

            Button("Skip") {
                viewModel.showMoodSelector = false
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Animations

    private func animateCheckmark() {
        showCheckmark = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
            checkmarkScale = 1.2
            checkmarkOpacity = 1.0
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.2)) {
            checkmarkScale = 1.0
        }
        // Transition to checked-in state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showCheckmark = false
        }
    }
}

struct MoodButton: View {
    let mood: Mood
    let emoji: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 44))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select mood: \(label)")
        .accessibilityHint("Double tap to select \(label) mood")
    }
}
