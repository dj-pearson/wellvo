import SwiftUI

/// A compact chip showing a flame + streak count. Only renders at streak >= 2
/// (shorter streaks don't feel like streaks yet). Use next to a name on
/// ReceiverStatusCard or on the Receiver home header.
///
/// At milestone thresholds (7, 30, 100, 365) the chip lights up with a brand
/// gradient fill + an orbiting sparkle that loops while the milestone is held.
struct StreakChip: View {
    let streakDays: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var sparklePhase: CGFloat = 0

    /// Flame color, darkened under Increase Contrast so it doesn't wash out on
    /// the cream chip (US-IOS106).
    private var flameColor: Color {
        contrast == .increased
            ? Color(red: 0.78, green: 0.30, blue: 0.02)
            : Color(red: 0.976, green: 0.451, blue: 0.086)
    }

    /// Light-mode streak-number color, darkened under Increase Contrast.
    private var numberColorLight: Color {
        contrast == .increased
            ? Color(red: 0.44, green: 0.13, blue: 0.04)
            : Color(red: 0.604, green: 0.204, blue: 0.071)
    }

    private static let milestones: Set<Int> = [7, 14, 30, 60, 100, 180, 365]

    private var isMilestone: Bool { Self.milestones.contains(streakDays) }

    var body: some View {
        if streakDays < 2 {
            EmptyView()
        } else if isMilestone {
            milestoneChip
        } else {
            standardChip
        }
    }

    private var standardChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(flameColor)
            Text("\(streakDays)")
                .font(.caption.weight(.bold))
                .foregroundStyle(scheme == .dark ? DailyOKColor.goldLight : numberColorLight)
                .contentTransition(.numericText(value: Double(streakDays)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            // Warm cream in light mode; a translucent ember tint in dark mode so
            // the chip doesn't sit as a bright patch on a dark surface.
            Capsule().fill(scheme == .dark
                ? Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.22)
                : Color(red: 1.0, green: 0.945, blue: 0.859))
        )
        .accessibilityElement()
        .accessibilityLabel("\(streakDays) day streak")
    }

    private var milestoneChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            Text("\(streakDays)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(streakDays)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [DailyOKColor.gold, Color(red: 0.976, green: 0.451, blue: 0.086)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75)
                )
        )
        .overlay(sparkleOverlay)
        .shadow(color: DailyOKColor.gold.opacity(0.35), radius: 8, y: 2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                sparklePhase = .pi * 2
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Milestone: \(streakDays) day streak")
    }

    private var sparkleOverlay: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let angle = sparklePhase + CGFloat(index) * (2 * .pi / 3)
                    let rx = geo.size.width * 0.48
                    let ry = geo.size.height * 0.7
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(
                            x: cos(angle) * rx,
                            y: sin(angle) * ry
                        )
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }
}

/// A tiny medal chip denoting the week's consistency tier.
/// Returns EmptyView for .none.
struct ConsistencyChip: View {
    let badge: ConsistencyBadge
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch badge {
        case .none:
            EmptyView()
        case .gold:
            chip(light: (Color(red: 0.996, green: 0.953, blue: 0.780), DailyOKColor.gold),
                 dark: (DailyOKColor.gold.opacity(0.22), DailyOKColor.goldLight),
                 label: "Gold")
        case .silver:
            chip(light: (Color(red: 0.898, green: 0.906, blue: 0.922), Color(red: 0.420, green: 0.447, blue: 0.502)),
                 dark: (Color(white: 0.6).opacity(0.28), Color(white: 0.88)),
                 label: "Silver")
        case .bronze:
            chip(light: (Color(red: 0.996, green: 0.843, blue: 0.667), Color(red: 0.761, green: 0.255, blue: 0.047)),
                 dark: (Color(red: 0.761, green: 0.255, blue: 0.047).opacity(0.28), Color(red: 0.95, green: 0.62, blue: 0.42)),
                 label: "Bronze")
        }
    }

    private func chip(light: (bg: Color, fg: Color), dark: (bg: Color, fg: Color), label: String) -> some View {
        let palette = scheme == .dark ? dark : light
        return HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(palette.bg))
        .accessibilityElement()
        .accessibilityLabel("\(label) consistency badge")
    }
}
