import SwiftUI

/// A celebratory overlay that briefly shows a scale+fade checkmark with a
/// particle ring burst after a successful action (e.g. check-in).
///
/// Usage: drive `isVisible` from the parent screen. The overlay calls
/// `onComplete` after ~1s so the parent can dismiss it.
/// Honors `accessibilityReduceMotion` — when enabled, shows only the
/// static checkmark without the ring animation.
struct CelebrationOverlay: View {
    @Binding var isVisible: Bool
    var onComplete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: CGFloat = 0
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            if isVisible {
                ZStack {
                    if !reduceMotion {
                        Circle()
                            .stroke(WellvoColor.green400.opacity(0.6 * (1 - Double(ringProgress))), lineWidth: 8)
                            .frame(width: 220 * ringProgress, height: 220 * ringProgress)
                        Circle()
                            .stroke(WellvoColor.green400.opacity(0.3 * (1 - Double(ringProgress))), lineWidth: 4)
                            .frame(width: 150 * ringProgress, height: 150 * ringProgress)
                    }

                    ZStack {
                        Circle()
                            .fill(WellvoColor.green500)
                            .frame(width: 96, height: 96)
                        Image(systemName: "checkmark")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                }
                .accessibilityElement()
                .accessibilityLabel("Success")
                .onAppear {
                    withAnimation(WellvoMotion.bouncySpring) {
                        scale = 1.0
                        opacity = 1.0
                    }
                    if !reduceMotion {
                        withAnimation(.easeOut(duration: WellvoMotion.durationExtraLong + 0.2)) {
                            ringProgress = 1.0
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeIn(duration: WellvoMotion.durationShort)) {
                            opacity = 0
                            scale = 1.2
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + WellvoMotion.durationShort) {
                            ringProgress = 0
                            scale = 0.4
                            onComplete()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
