import SwiftUI

/// Guided steps to get Daily OK onto a loved one's Apple Watch (and a widget
/// fallback for those without a watch). The watch features only deliver value if
/// seniors actually get them installed — this closes that adoption gap.
struct WatchSetupGuideView: View {
    private struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let watchSteps: [Step] = [
        Step(icon: "applewatch",
             title: "Install on the Apple Watch",
             detail: "On the iPhone paired to their watch, open the Watch app → scroll to “Daily OK” → tap Install. Or it installs automatically if “Automatic App Install” is on."),
        Step(icon: "circle.grid.2x2",
             title: "Add the watch-face complication",
             detail: "Touch and hold the watch face → Edit → choose a complication slot → pick Daily OK. Now checking in is one tap from the face, and a green check shows when they're done for the day."),
        Step(icon: "bell.badge",
             title: "Allow notifications on the watch",
             detail: "In the iPhone Watch app → Notifications, make sure Daily OK is allowed so the check-in reminder appears on their wrist with the “I'm OK” button."),
        Step(icon: "hand.tap",
             title: "Tap “I'm OK” to check in",
             detail: "They can tap the complication, the giant button in the watch app, or the “I'm OK” action right on the reminder — no need to reach for the phone."),
    ]

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 44))
                        .foregroundStyle(DailyOKColor.green500)
                    Text("Set up Daily OK on their Apple Watch")
                        .font(.title3).fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    Text("The easiest way for someone to check in — one tap on the wrist, no phone required.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Steps") {
                ForEach(Array(watchSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(DailyOKColor.green500.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: step.icon).foregroundStyle(DailyOKColor.green600)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(index + 1). \(step.title)").font(.subheadline).fontWeight(.semibold)
                            Text(step.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No Apple Watch?").font(.subheadline).fontWeight(.semibold)
                        Text("Add the Daily OK widget to their iPhone Lock Screen or Home Screen for the same one-tap check-in: touch and hold the Lock Screen → Customize → add the Daily OK widget.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.iphone").foregroundStyle(DailyOKColor.teal)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Alternative")
            }
        }
        .navigationTitle("Apple Watch Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}
