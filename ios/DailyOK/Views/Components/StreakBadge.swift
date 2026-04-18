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
    @State private var sparklePhase: CGFloat = 0

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
                .foregroundStyle(Color(red: 0.976, green: 0.451, blue: 0.086))
            Text("\(streakDays)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.604, green: 0.204, blue: 0.071))
                .contentTransition(.numericText(value: Double(streakDays)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color(red: 1.0, green: 0.945, blue: 0.859))
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

    var body: some View {
        switch badge {
        case .none:
            EmptyView()
        case .gold:
            chip(background: Color(red: 0.996, green: 0.953, blue: 0.780), foreground: DailyOKColor.gold, label: "Gold")
        case .silver:
            chip(background: Color(red: 0.898, green: 0.906, blue: 0.922), foreground: Color(red: 0.420, green: 0.447, blue: 0.502), label: "Silver")
        case .bronze:
            chip(background: Color(red: 0.996, green: 0.843, blue: 0.667), foreground: Color(red: 0.761, green: 0.255, blue: 0.047), label: "Bronze")
        }
    }

    private func chip(background: Color, foreground: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
        .accessibilityElement()
        .accessibilityLabel("\(label) consistency badge")
    }
}
