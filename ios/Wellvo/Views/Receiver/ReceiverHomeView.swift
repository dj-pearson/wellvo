import SwiftUI

struct ReceiverHomeView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @State private var buttonScale: CGFloat = 1.0
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 40) {
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

            Button {
                Task { await viewModel.performCheckIn() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 200, height: 200)
                        .shadow(color: .green.opacity(0.4), radius: isPulsing ? 20 : 10)
                        .scaleEffect(buttonScale)

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
            }

            Text("Tap to let your family know you're OK")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
            }

            Text("Your family knows you're OK")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            if let checkIn = viewModel.lastCheckIn {
                Text("Checked in at \(checkIn.checkedInAt.formatted(date: .omitted, time: .shortened))")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mood Selector

    private var moodSelector: some View {
        VStack(spacing: 16) {
            Text("How are you feeling?")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                MoodButton(mood: .happy, emoji: "😊", label: "Good") {
                    Task { await viewModel.submitMood(.happy) }
                }

                MoodButton(mood: .neutral, emoji: "😐", label: "Okay") {
                    Task { await viewModel.submitMood(.neutral) }
                }

                MoodButton(mood: .tired, emoji: "😴", label: "Tired") {
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
            }
            .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feeling \(label)")
    }
}
