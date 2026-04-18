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

/// Floating, frosted-glass bottom navigation bar with a matched-geometry pill
/// indicator that smoothly slides between tabs. Blurs the content behind it
/// (`.ultraThinMaterial`) so the UI feels layered and modern.
struct FloatingBottomNav: View {
    let items: [FloatingNavItem]
    @Binding var selectedIndex: Int
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                NavItemView(
                    item: item,
                    selected: index == selectedIndex,
                    namespace: pillNamespace
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    DailyOKHaptics.selection()
                    withAnimation(DailyOKMotion.smoothSpring) {
                        selectedIndex = index
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassCard(style: .regular, radius: 32, elevation: DailyOKElevation.level4)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct NavItemView: View {
    let item: FloatingNavItem
    let selected: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
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
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)).animation(DailyOKMotion.smoothSpring),
                        removal: .opacity
                    ))
            }
        }
        .foregroundStyle(selected ? DailyOKColor.green700 : Color.secondary)
        .padding(.horizontal, selected ? 16 : 10)
        .padding(.vertical, 10)
        .background(
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [DailyOKColor.green100, DailyOKColor.green200.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(DailyOKColor.green300.opacity(0.5), lineWidth: 0.75)
                        )
                        .matchedGeometryEffect(id: "pill", in: namespace)
                }
            }
        )
        .accessibilityElement()
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }
}
