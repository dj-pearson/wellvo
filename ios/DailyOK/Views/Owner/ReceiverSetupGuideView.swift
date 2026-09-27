import SwiftUI

/// Step-by-step guide for owners helping someone they invited get set up.
/// Explains exactly what the receiver needs to do, including the setup code,
/// and can be shared with them or a helper.
struct ReceiverSetupGuideView: View {
    let receiverName: String
    /// The invite's 6-digit setup code, when known.
    var pairingCode: String? = nil
    @Environment(\.dismiss) var dismiss

    private var steps: [(icon: String, title: String, description: String)] {
        var steps: [(icon: String, title: String, description: String)] = [
            ("message.fill",
             String(localized: "Open your text"),
             String(localized: "\(receiverName) gets a text from your number. Tap the link in it to get Daily OK.")),
            ("person.crop.circle.badge.checkmark",
             String(localized: "Sign in, then tap the link again"),
             String(localized: "Open the app and sign in with Apple or an email. Then tap the link in the text once more — the app shows whose family it is before they join.")),
        ]
        if let code = pairingCode, !code.isEmpty {
            steps.append((
                "number",
                String(localized: "Or use the setup code"),
                String(localized: "On an iPad, or if the link doesn't open the app, enter the setup code \(code) when the app asks.")
            ))
        }
        steps.append((
            "bell.badge.fill",
            String(localized: "Allow notifications"),
            String(localized: "The daily check-in arrives as a notification, so this is required.")
        ))
        steps.append((
            "hand.thumbsup.fill",
            String(localized: "That's it"),
            String(localized: "Each day at the scheduled time, tap \"I'm OK.\"")
        ))
        return steps
    }

    /// The steps as plain text, to send to the receiver or whoever is helping.
    private var shareText: String {
        var lines = [String(localized: "Setting up Daily OK for \(receiverName):")]
        for (index, step) in steps.enumerated() {
            lines.append("\(index + 1). \(step.title) — \(step.description)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("What \(receiverName) needs to do")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        SetupStepRow(
                            stepNumber: index + 1,
                            icon: step.icon,
                            title: step.title,
                            description: step.description
                        )
                    }

                    ShareLink(item: shareText) {
                        Label("Send these steps", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Tips", systemImage: "lightbulb.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        TipRow(text: "If the link opens the App Store instead of the app, \(receiverName) can tap it again after installing, or enter the setup code.")
                        TipRow(text: "If the text didn't arrive, check the number in the Family tab and re-send the invite. A re-sent invite replaces the old link and code.")
                        TipRow(text: "You can change the check-in time anytime from the Family tab.")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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

    /// Grows with Dynamic Type instead of clipping the number.
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // green700 keeps white text above 4.5:1 (systemGreen was ~2.2:1).
            Text("\(stepNumber)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(minWidth: badgeSize, minHeight: badgeSize)
                .background(Circle().fill(DailyOKColor.green700))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(DailyOKColor.green700)
                        .accessibilityHidden(true)
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
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
