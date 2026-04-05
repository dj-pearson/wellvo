import SwiftUI

/// A hero card with a soft brand gradient background. Use sparingly for the
/// highest-priority information on a screen (weekly summary, streak highlight,
/// premium-feature teasers).
struct GradientHeroCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailingSystemImage: String? = nil
    var trailingAccessibilityLabel: String? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String? = nil,
        trailingSystemImage: String? = nil,
        trailingAccessibilityLabel: String? = nil,
        @ViewBuilder content: @escaping () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingSystemImage = trailingSystemImage
        self.trailingAccessibilityLabel = trailingAccessibilityLabel
        self.content = content
    }

    private var gradient: LinearGradient {
        let stops: [Color] = colorScheme == .dark
            ? [WellvoColor.green900, WellvoColor.surfaceDarkHigh]
            : [WellvoColor.green50, WellvoColor.green100]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : WellvoColor.green900
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? WellvoColor.green100 : WellvoColor.green700
    }

    private var iconTint: Color {
        colorScheme == .dark ? WellvoColor.green400 : WellvoColor.green700
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(titleColor)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(subtitleColor)
                    }
                }
                Spacer()
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .accessibilityLabel(trailingAccessibilityLabel ?? "")
                        .accessibilityHidden(trailingAccessibilityLabel == nil)
                }
            }
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(gradient)
        )
        .wellvoShadow(WellvoElevation.level2, opacity: 0.10)
    }
}

/// A compact stat card showing a prominent value, a descriptive label, and an
/// optional delta indicator. Designed to tile 2-3 across on a dashboard row.
struct PremiumStatCard: View {
    let value: String
    let label: String
    var accent: Color? = nil
    var delta: StatDelta? = nil

    private var resolvedAccent: Color { accent ?? WellvoColor.brand }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(resolvedAccent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let delta {
                HStack(spacing: 3) {
                    Image(systemName: delta.positive ? "arrow.up" : "arrow.down")
                        .font(.caption2.weight(.bold))
                    Text(delta.label)
                        .font(.caption2)
                }
                .foregroundStyle(delta.positive ? WellvoColor.brand : WellvoColor.error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .wellvoShadow(WellvoElevation.level1, opacity: 0.06)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct StatDelta {
    let label: String
    let positive: Bool
}
