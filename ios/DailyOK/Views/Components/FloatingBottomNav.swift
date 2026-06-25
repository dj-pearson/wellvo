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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                NavItemView(
                    item: item,
                    selected: index == selectedIndex,
                    namespace: pillNamespace,
                    reduceMotion: reduceMotion
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    DailyOKHaptics.selection()
                    withAnimation(reduceMotion ? nil : DailyOKMotion.smoothSpring) {
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
    var reduceMotion: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: reduceMotion ? false : selected)
                if item.badgeCount > 0 {
                    // Clamp so a large count can't blow out the capsule.
                    Text(item.badgeCount > 99 ? "99+" : "\(item.badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DailyOKColor.error))
                        .offset(x: 8, y: -6)
                }
            }
            // Hide the label at accessibility text sizes so a long/large label
            // can't truncate the icon or overflow the pill.
            if selected && !dynamicTypeSize.isAccessibilitySize {
                Text(item.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)).animation(reduceMotion ? nil : DailyOKMotion.smoothSpring),
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
        // Guarantee a 44pt tap target even for the smaller unselected items
        // (US-IOS105).
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(item.label)
        .accessibilityValue(item.badgeCount > 0 ? "\(item.badgeCount) new" : "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }
}
