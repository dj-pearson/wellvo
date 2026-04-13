import SwiftUI

/// A compact chip showing a flame + streak count. Only renders at streak >= 2
/// (shorter streaks don't feel like streaks yet). Use next to a name on
/// ReceiverStatusCard or on the Receiver home header.
struct StreakChip: View {
    let streakDays: Int

    var body: some View {
        if streakDays < 2 {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.976, green: 0.451, blue: 0.086))
                Text("\(streakDays)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.604, green: 0.204, blue: 0.071))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(red: 1.0, green: 0.945, blue: 0.859))
            )
            .accessibilityElement()
            .accessibilityLabel("\(streakDays) day streak")
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
