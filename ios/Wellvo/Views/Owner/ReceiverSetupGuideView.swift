import SwiftUI

/// Step-by-step guide shown to owners after they send a receiver invite.
/// Explains exactly what the receiver needs to do to get set up.
struct ReceiverSetupGuideView: View {
    let receiverName: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)

                        Text("Invite Sent!")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("\(receiverName) will receive a text message with instructions to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

                    Divider()

                    // Steps header
                    Text("What \(receiverName) needs to do:")
                        .font(.headline)

                    // Step 1
                    SetupStepRow(
                        stepNumber: 1,
                        icon: "message.fill",
                        title: "Open the Text Message",
                        description: "\(receiverName) will receive a text with a link to download Alive from the App Store."
                    )

                    // Step 2
                    SetupStepRow(
                        stepNumber: 2,
                        icon: "arrow.down.app.fill",
                        title: "Download the App",
                        description: "Tap the link in the text to open the App Store and download Alive."
                    )

                    // Step 3
                    SetupStepRow(
                        stepNumber: 3,
                        icon: "phone.fill",
                        title: "Sign In with Their Phone Number",
                        description: "Open the app and enter the same phone number the text was sent to. They'll receive a verification code."
                    )

                    // Step 4
                    SetupStepRow(
                        stepNumber: 4,
                        icon: "bell.badge.fill",
                        title: "Allow Notifications",
                        description: "The app will ask to send notifications. This is required so they receive their daily check-in reminder."
                    )

                    // Step 5
                    SetupStepRow(
                        stepNumber: 5,
                        icon: "hand.thumbsup.fill",
                        title: "That's It!",
                        description: "The app automatically connects them to your family. Each day at the scheduled time, they just tap \"I'm OK.\""
                    )

                    Divider()

                    // Tips section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Tips", systemImage: "lightbulb.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)

                        TipRow(text: "Make sure \(receiverName) uses the exact phone number you entered when signing in.")
                        TipRow(text: "If they don't see the text, check that the phone number is correct and try re-sending the invite.")
                        TipRow(text: "The app will automatically match them to your family — no codes or links to enter.")
                        TipRow(text: "You can adjust the check-in schedule anytime from the Family tab.")
                    }
                    .padding()
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Step Row

private struct SetupStepRow: View {
    let stepNumber: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: 32, height: 32)

                Text("\(stepNumber)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tip Row

private struct TipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
