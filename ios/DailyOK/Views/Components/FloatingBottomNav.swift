import SwiftUI

struct FloatingNavItem: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let badgeCount: Int

    init(label: String, systemImage: String, badgeCount: Int = 0) {
        self.label = label
        self.systemImage = systemImage
        self.badgeCount = badgeCount
    }
}

/// Floating, rounded bottom navigation bar with a pill indicator behind the
/// selected tab. Can be overlaid on top of a `ZStack`-based tab layout as an
/// alternative to SwiftUI's standard `TabView`. Adopt incrementally — not a
/// drop-in replacement for existing `.tabItem` screens.
struct FloatingBottomNav: View {
    let items: [FloatingNavItem]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                NavItemView(
                    item: item,
                    selected: index == selectedIndex
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DailyOKMotion.smoothSpring) {
                        selectedIndex = index
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .dailyokShadow(DailyOKElevation.level4, opacity: 0.12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct NavItemView: View {
    let item: FloatingNavItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                if item.badgeCount > 0 {
                    Text("\(item.badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DailyOKColor.error))
                        .offset(x: 8, y: -6)
                }
            }
            if selected {
                Text(item.label)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(selected ? DailyOKColor.green700 : Color.secondary)
        .padding(.horizontal, selected ? 14 : 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(selected ? DailyOKColor.green100 : Color.clear)
        )
        .accessibilityElement()
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }
}
