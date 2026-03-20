import SwiftUI

struct ReceiverHomeView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var buttonScale: CGFloat = 1.0
    @State private var isPulsing = false
    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0
    @ScaledMetric(relativeTo: .largeTitle) private var buttonDiameter: CGFloat = 200
    @ScaledMetric(relativeTo: .title) private var tapIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var tapTextSize: CGFloat = 28

    private let hapticSuccess = UINotificationFeedbackGenerator()
    private let hapticImpact = UIImpactFeedbackGenerator(style: .medium)

    @State private var notificationBanner = NotificationPermissionBanner()

    private var isKidMode: Bool {
        viewModel.receiverMode == .kid
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
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
                        .frame(height: 20)

                    if viewModel.hasCheckedInToday {
                        statusCard
                            .padding(.horizontal)

                        if isKidMode {
                            kidMoodSelector
                                .padding(.horizontal)

                            kidLocationPicker
                                .padding(.horizontal)

                            kidResponseButtons
                                .padding(.horizontal)
                        }
                    } else {
                        checkInButton
                    }

                    Spacer()
                        .frame(height: 20)

                    // Mood selector overlay (standard mode only)
                    if viewModel.showMoodSelector && !isKidMode {
                        moodSelector
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .transaction { t in if reduceMotion { t.animation = nil } }
                    }
                }
                .padding()
            }
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
                    if isKidMode {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.green, .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: buttonDiameter, height: buttonDiameter)
                            .shadow(color: .teal.opacity(0.4), radius: isPulsing ? 20 : 10)
                            .scaleEffect(buttonScale)
                    } else {
                        Circle()
                            .fill(Color.green)
                            .frame(width: buttonDiameter, height: buttonDiameter)
                            .shadow(color: .green.opacity(0.4), radius: isPulsing ? 20 : 10)
                            .scaleEffect(buttonScale)
                    }

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
                                .font(.system(size: tapIconSize))
                                .foregroundStyle(.white)

                            Text(isKidMode ? "I'm OK! 👋" : "I'm OK")
                                .font(.system(size: tapTextSize, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .disabled(viewModel.isCheckingIn)
            .accessibilityLabel("Tap to check in and let your family know you're okay")
            .onAppear {
                guard !reduceMotion else { return }
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

    // MARK: - Post-Check-In Status Card

    private var statusCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: reduceMotion ? false : viewModel.hasCheckedInToday)
                .accessibilityHidden(true)

            Text(isKidMode ? "Awesome! Your parents know you're OK! 🎉" : "You're all set!")
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

            if let nextTime = viewModel.nextCheckInTime {
                Text("Next check-in: Tomorrow at \(nextTime.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text("Your family has been notified")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checked in successfully. Your family has been notified.")
    }

    // MARK: - Kid Mode: Mood Selector (2x4 grid)

    private var kidMoodSelector: some View {
        VStack(spacing: 12) {
            Text("How are you feeling?")
                .font(.headline)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(Mood.kidMoods, id: \.self) { mood in
                    kidMoodButton(mood: mood)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func kidMoodButton(mood: Mood) -> some View {
        Button {
            hapticImpact.impactOccurred()
            Task { await viewModel.submitMood(mood) }
        } label: {
            VStack(spacing: 6) {
                Text(mood.emoji)
                    .font(.system(size: 32))
                Text(mood.label)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.selectedMood == mood
                          ? Color.accentColor.opacity(0.2)
                          : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.selectedMood == mood ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select mood: \(mood.label)")
        .accessibilityHint("Double tap to select \(mood.label) mood")
    }

    // MARK: - Kid Mode: Location Label Picker (3x2 grid)

    private var kidLocationPicker: some View {
        VStack(spacing: 12) {
            Text("Where are you?")
                .font(.headline)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(LocationLabel.allCases, id: \.self) { location in
                    Button {
                        hapticImpact.impactOccurred()
                        viewModel.submitLocationLabel(location)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: location.icon)
                                .font(.title2)
                            Text(location.label)
                                .font(.caption)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.selectedLocationLabel == location
                                      ? Color.accentColor.opacity(0.2)
                                      : Color(.tertiarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(viewModel.selectedLocationLabel == location ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Location: \(location.label)")
                    .accessibilityHint("Double tap to select \(location.label)")
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Kid Mode: Response Buttons

    private var kidResponseButtons: some View {
        VStack(spacing: 12) {
            Text("Need anything?")
                .font(.headline)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            HStack(spacing: 12) {
                // Pick me up
                Button {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitKidResponse(.pickingMeUp) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: KidResponseType.pickingMeUp.icon)
                            .font(.title3)
                        Text(KidResponseType.pickingMeUp.label)
                            .font(.caption)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.selectedKidResponse == .pickingMeUp
                                  ? Color.orange.opacity(0.3)
                                  : Color.orange.opacity(0.1))
                    )
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Request: \(KidResponseType.pickingMeUp.label)")

                // Can I stay longer
                Button {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitKidResponse(.canStayLonger) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: KidResponseType.canStayLonger.icon)
                            .font(.title3)
                        Text(KidResponseType.canStayLonger.label)
                            .font(.caption)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.selectedKidResponse == .canStayLonger
                                  ? Color.blue.opacity(0.3)
                                  : Color.blue.opacity(0.1))
                    )
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Request: \(KidResponseType.canStayLonger.label)")

                // SOS
                Button {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitKidResponse(.sos) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: KidResponseType.sos.icon)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(KidResponseType.sos.label)
                            .font(.caption)
                            .fontWeight(.bold)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("SOS: Send emergency alert to your family")
                .accessibilityHint("Double tap to send an SOS alert")
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Mood Selector (Standard Mode)

    private var moodSelector: some View {
        VStack(spacing: 16) {
            Text("How are you feeling?")
                .font(.headline)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            HStack(spacing: 24) {
                MoodButton(mood: .happy, emoji: Mood.happy.emoji, label: Mood.happy.label) {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitMood(.happy) }
                }

                MoodButton(mood: .neutral, emoji: Mood.neutral.emoji, label: Mood.neutral.label) {
                    hapticImpact.impactOccurred()
                    Task { await viewModel.submitMood(.neutral) }
                }

                MoodButton(mood: .tired, emoji: Mood.tired.emoji, label: Mood.tired.label) {
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
        if reduceMotion {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showCheckmark = false
            }
        } else {
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
