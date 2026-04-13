import SwiftUI

/// Reusable friendly empty state with a large tinted icon, title, message text,
/// and optional primary/secondary actions. Replaces ad-hoc VStack+Image+Text
/// empty states scattered across screens.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryActionLabel: String? = nil
    var onPrimaryAction: (() -> Void)? = nil
    var secondaryActionLabel: String? = nil
    var onSecondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green100)
                    .frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(DailyOKColor.green700)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let primaryActionLabel, let onPrimaryAction {
                Button(action: onPrimaryAction) {
                    Text(primaryActionLabel)
                        .fontWeight(.semibold)
                        .frame(minWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.brand)
                .padding(.top, 4)
            }

            if let secondaryActionLabel, let onSecondaryAction {
                Button(secondaryActionLabel, action: onSecondaryAction)
                    .font(.subheadline)
                    .foregroundStyle(DailyOKColor.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
