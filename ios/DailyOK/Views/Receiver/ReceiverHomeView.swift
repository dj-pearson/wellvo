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

    private var isKidMode: Bool {
        viewModel.receiverMode == .kid
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    NotificationPermissionBanner()
                        .padding(.horizontal)

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

                    Spacer().frame(height: 20)

                    if viewModel.hasCheckedInToday {
                        statusCard.padding(.horizontal)
                    } else {
                        checkInButton
                    }

                    if let errorMessage = viewModel.errorMessage {
                        VStack(spacing: 12) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)

                            Button {
                                Task { await viewModel.performCheckIn() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Try Again")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(minWidth: 120, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        .padding(.horizontal)
                    }

                    Spacer().frame(height: 20)
                }
                .padding()
            }
        }
        .task { await viewModel.loadStatus() }
    }

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showCheckmark = false
            }
        }
    }
}
