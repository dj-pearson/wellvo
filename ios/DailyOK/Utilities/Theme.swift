import SwiftUI

/// Daily OK design tokens — colors, elevation, motion.
///
/// This is the single source of truth for the app's visual language. Every
/// screen should prefer these tokens to hardcoded values so that the premium
/// feel stays consistent and changes propagate everywhere.
enum DailyOKColor {
    // MARK: Brand green tonal ramp
    static let green50  = Color(red: 0.941, green: 0.992, blue: 0.957) // #F0FDF4
    static let green100 = Color(red: 0.863, green: 0.988, blue: 0.906) // #DCFCE7
    static let green200 = Color(red: 0.733, green: 0.969, blue: 0.816) // #BBF7D0
    static let green300 = Color(red: 0.525, green: 0.937, blue: 0.675) // #86EFAC
    static let green400 = Color(red: 0.290, green: 0.871, blue: 0.502) // #4ADE80
    static let green500 = Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E — primary brand
    static let green600 = Color(red: 0.086, green: 0.639, blue: 0.290) // #16A34A
    static let green700 = Color(red: 0.082, green: 0.502, blue: 0.239) // #15803D
    static let green800 = Color(red: 0.086, green: 0.396, blue: 0.204) // #166534
    static let green900 = Color(red: 0.078, green: 0.325, blue: 0.176) // #14532D

    /// Primary brand color, resolves to green500.
    static let brand = green500

    // MARK: Premium accents
    static let teal = Color(red: 0.078, green: 0.722, blue: 0.651)       // #14B8A6
    static let gold = Color(red: 0.961, green: 0.620, blue: 0.043)       // #F59E0B — paid features
    static let goldLight = Color(red: 0.992, green: 0.906, blue: 0.541)  // #FDE68A
    static let indigo = Color(red: 0.388, green: 0.400, blue: 0.945)     // #6366F1

    // MARK: Tonal surfaces (light)
    static let surfaceLight = Color.white
    static let surfaceLightLow = Color(red: 0.976, green: 0.980, blue: 0.984)   // #F9FAFB
    static let surfaceLightMed = Color(red: 0.953, green: 0.957, blue: 0.961)   // #F3F4F6
    static let surfaceLightHigh = Color(red: 0.898, green: 0.906, blue: 0.922)  // #E5E7EB

    // MARK: Tonal surfaces (dark) — subtly tinted toward brand green
    static let surfaceDark = Color(red: 0.043, green: 0.078, blue: 0.063)       // #0B1410
    static let surfaceDarkLow = Color(red: 0.059, green: 0.102, blue: 0.078)    // #0F1A14
    static let surfaceDarkMed = Color(red: 0.078, green: 0.133, blue: 0.098)    // #142219
    static let surfaceDarkHigh = Color(red: 0.106, green: 0.173, blue: 0.133)   // #1B2C22

    // MARK: Semantic
    static let error = Color(red: 0.937, green: 0.267, blue: 0.267)   // #EF4444
    static let warning = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B
    static let info = Color(red: 0.231, green: 0.510, blue: 0.965)    // #3B82F6
}

/// Motion tokens — durations and spring responses for consistent feel.
enum DailyOKMotion {
    static let durationInstant: Double = 0.05
    static let durationShort: Double = 0.15
    static let durationMedium: Double = 0.25
    static let durationLong: Double = 0.40
    static let durationExtraLong: Double = 0.60

    /// Standard spring for card appearance and tab transitions.
    static let smoothSpring: Animation = .spring(response: 0.45, dampingFraction: 0.85)

    /// Bouncy spring for check-in button press and success reveals.
    static let bouncySpring: Animation = .spring(response: 0.35, dampingFraction: 0.6)

    /// Linear easing for shimmer / progress loops.
    static let linear: Animation = .linear(duration: durationExtraLong * 2)
}

/// Elevation tokens — pair with SwiftUI `.shadow(...)`.
enum DailyOKElevation {
    static let level0: CGFloat = 0
    static let level1: CGFloat = 2
    static let level2: CGFloat = 6
    static let level3: CGFloat = 12
    static let level4: CGFloat = 18
    static let level5: CGFloat = 24
}

extension View {
    /// Apply a Daily OK elevation shadow consistent with the design system.
    func dailyokShadow(_ level: CGFloat, opacity: Double = 0.08) -> some View {
        shadow(
            color: Color.black.opacity(opacity),
            radius: level,
            x: 0,
            y: level * 0.4
        )
    }
}

// MARK: - Glass (Glassmorphism) tokens

/// Glass material tokens — pair with `.glassCard(...)` for consistent frosted surfaces.
enum DailyOKGlass {
    /// Corner radii for glass surfaces — roomy and organic.
    static let radiusSmall: CGFloat = 14
    static let radiusMedium: CGFloat = 20
    static let radiusLarge: CGFloat = 28
    static let radiusXL: CGFloat = 36

    /// Hairline stroke used to catch ambient light on glass surfaces.
    static let strokeLight = Color.white.opacity(0.45)
    static let strokeDark = Color.white.opacity(0.14)

    /// Subtle tint layered over the blur to keep brand presence.
    static let tintLight = DailyOKColor.green50.opacity(0.35)
    static let tintDark = DailyOKColor.green900.opacity(0.45)
}

/// Glass depth variants — each maps to a SwiftUI material.
enum DailyOKGlassStyle {
    case ultraThin   // lightest — floating chips, toolbars
    case thin        // cards, list rows overlaid on content
    case regular     // bottom sheets, modal cards
    case thick       // full-screen overlays, paywall

    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin:      return .thinMaterial
        case .regular:   return .regularMaterial
        case .thick:     return .thickMaterial
        }
    }
}

extension View {
    /// Apply a branded glassmorphism surface: blurred material + subtle tint + hairline stroke.
    ///
    /// - Parameters:
    ///   - style: The material depth — see ``DailyOKGlassStyle``.
    ///   - radius: Corner radius token. Defaults to `DailyOKGlass.radiusLarge`.
    ///   - elevation: Shadow depth for the floating effect.
    func glassCard(
        style: DailyOKGlassStyle = .regular,
        radius: CGFloat = DailyOKGlass.radiusLarge,
        elevation: CGFloat = DailyOKElevation.level3
    ) -> some View {
        modifier(GlassCardModifier(style: style, radius: radius, elevation: elevation))
    }

    /// Lightweight glass surface — skips shadow + stroke for inline chips/pills.
    func glassPill(
        style: DailyOKGlassStyle = .ultraThin,
        radius: CGFloat = 999
    ) -> some View {
        background(style.material, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(DailyOKGlass.strokeLight, lineWidth: 0.75)
                    .blendMode(.overlay)
            )
            .clipShape(Capsule())
    }
}

private struct GlassCardModifier: ViewModifier {
    let style: DailyOKGlassStyle
    let radius: CGFloat
    let elevation: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                shape
                    .fill(style.material)
                    .overlay(
                        shape.fill(scheme == .dark ? DailyOKGlass.tintDark : DailyOKGlass.tintLight)
                    )
            )
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [DailyOKGlass.strokeDark, Color.white.opacity(0.02)]
                                : [DailyOKGlass.strokeLight, Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .clipShape(shape)
            .dailyokShadow(elevation, opacity: scheme == .dark ? 0.35 : 0.12)
    }
}

// MARK: - Ambient background

/// Full-screen ambient gradient mesh used behind glass layers. The colors
/// breathe slowly so the app feels alive without distracting from content.
struct AmbientBackground: View {
    enum Tone { case calm, warm, alert, neutral }

    var tone: Tone = .calm
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                baseColor
                ForEach(Array(orbs.enumerated()), id: \.offset) { idx, orb in
                    Circle()
                        .fill(orb.color)
                        .frame(width: geo.size.width * orb.size, height: geo.size.width * orb.size)
                        .blur(radius: 80)
                        .offset(
                            x: geo.size.width * orb.x + sin(phase + CGFloat(idx)) * 24,
                            y: geo.size.height * orb.y + cos(phase + CGFloat(idx) * 1.3) * 24
                        )
                        .opacity(scheme == .dark ? 0.55 : 0.7)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }

    private var baseColor: Color {
        switch (tone, scheme) {
        case (_, .dark): return DailyOKColor.surfaceDark
        case (.calm, _): return DailyOKColor.green50
        case (.warm, _): return Color(red: 1.0, green: 0.976, blue: 0.925)
        case (.alert, _): return Color(red: 0.996, green: 0.949, blue: 0.937)
        case (.neutral, _): return DailyOKColor.surfaceLightLow
        }
    }

    private struct Orb { let color: Color; let size: CGFloat; let x: CGFloat; let y: CGFloat }

    private var orbs: [Orb] {
        switch tone {
        case .calm:
            return [
                Orb(color: DailyOKColor.green300, size: 0.9, x: -0.15, y: -0.1),
                Orb(color: DailyOKColor.teal.opacity(0.6), size: 0.8, x: 0.55, y: 0.15),
                Orb(color: DailyOKColor.green100, size: 1.1, x: 0.1, y: 0.7)
            ]
        case .warm:
            return [
                Orb(color: DailyOKColor.goldLight, size: 0.95, x: -0.1, y: -0.05),
                Orb(color: DailyOKColor.gold.opacity(0.45), size: 0.75, x: 0.6, y: 0.2),
                Orb(color: DailyOKColor.green200, size: 1.0, x: 0.2, y: 0.75)
            ]
        case .alert:
            return [
                Orb(color: DailyOKColor.warning.opacity(0.45), size: 0.85, x: -0.1, y: 0),
                Orb(color: DailyOKColor.error.opacity(0.3), size: 0.75, x: 0.55, y: 0.25),
                Orb(color: DailyOKColor.green100, size: 0.95, x: 0.15, y: 0.75)
            ]
        case .neutral:
            return [
                Orb(color: DailyOKColor.indigo.opacity(0.25), size: 0.8, x: -0.1, y: -0.1),
                Orb(color: DailyOKColor.green200, size: 0.9, x: 0.55, y: 0.2),
                Orb(color: DailyOKColor.teal.opacity(0.3), size: 1.0, x: 0.1, y: 0.7)
            ]
        }
    }
}

// MARK: - Press feedback

/// Press-and-release scale + opacity treatment for primary CTAs.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var dim: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? dim : 1.0)
            .animation(DailyOKMotion.bouncySpring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Glass sheet presentation

extension View {
    /// Apply branded glass presentation to a sheet: translucent material background,
    /// branded drag handle, consistent rounded corners.
    ///
    /// Requires iOS 16.4+ for `.presentationBackground`. On older iOS versions
    /// falls back to the system default.
    @ViewBuilder
    func dailyokGlassSheet(
        style: DailyOKGlassStyle = .regular,
        cornerRadius: CGFloat = DailyOKGlass.radiusXL
    ) -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationBackground(style.material)
                .presentationCornerRadius(cornerRadius)
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}
