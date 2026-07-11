import SwiftUI

/// A celebratory overlay that briefly shows a scale+fade checkmark with a
/// particle ring burst + confetti after a successful action (e.g. check-in).
///
/// Usage: drive `isVisible` from the parent screen. The overlay calls
/// `onComplete` after ~1.2s so the parent can dismiss it.
/// Honors `accessibilityReduceMotion` — when enabled, shows only the
/// static checkmark without the ring or confetti animation.
struct CelebrationOverlay: View {
    @Binding var isVisible: Bool
    var onComplete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: CGFloat = 0
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0
    @State private var confettiProgress: CGFloat = 0
    @State private var confettiPieces: [ConfettiPiece] = []
    /// Drives the auto-dismiss so it can be cancelled if the parent hides the
    /// overlay early (otherwise onComplete fires on a torn-down view).
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isVisible {
                if !reduceMotion {
                    ConfettiLayer(pieces: confettiPieces, progress: confettiProgress)
                        .allowsHitTesting(false)
                }

                ZStack {
                    if !reduceMotion {
                        Circle()
                            .stroke(DailyOKColor.green400.opacity(0.6 * (1 - Double(ringProgress))), lineWidth: 8)
                            .frame(width: 220 * ringProgress, height: 220 * ringProgress)
                        Circle()
                            .stroke(DailyOKColor.green400.opacity(0.3 * (1 - Double(ringProgress))), lineWidth: 4)
                            .frame(width: 150 * ringProgress, height: 150 * ringProgress)
                    }

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DailyOKColor.green400, DailyOKColor.green600],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 96, height: 96)
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                            )
                        Image(systemName: "checkmark")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel("Success")
                .onAppear {
                    if reduceMotion {
                        // Honor the documented contract: a static reveal, no
                        // bounce/scale, for users who enabled Reduce Motion to
                        // avoid vestibular discomfort. (The entrance spring and
                        // the 1.2x dismiss scale below were previously applied
                        // unconditionally, contradicting the doc comment.)
                        scale = 1.0
                        opacity = 1.0
                    } else {
                        confettiPieces = ConfettiPiece.spawn(count: 36)
                        withAnimation(DailyOKMotion.bouncySpring) {
                            scale = 1.0
                            opacity = 1.0
                        }
                        withAnimation(.easeOut(duration: DailyOKMotion.durationExtraLong + 0.2)) {
                            ringProgress = 1.0
                        }
                        withAnimation(.easeOut(duration: 1.1)) {
                            confettiProgress = 1.0
                        }
                    }
                    // Announce for VoiceOver users, who may never have the element focused.
                    UIAccessibility.post(notification: .announcement, argument: String(localized: "Success"))

                    // Cancellable auto-dismiss: bail if the overlay was hidden early
                    // so we don't mutate state or call onComplete on a torn-down view.
                    dismissTask?.cancel()
                    dismissTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled, isVisible else { return }
                        withAnimation(.easeIn(duration: DailyOKMotion.durationShort)) {
                            opacity = 0
                            // Fade only under Reduce Motion; no scale-up.
                            if !reduceMotion { scale = 1.2 }
                        }
                        try? await Task.sleep(nanoseconds: UInt64(DailyOKMotion.durationShort * 1_000_000_000))
                        guard !Task.isCancelled, isVisible else { return }
                        ringProgress = 0
                        scale = 0.4
                        confettiProgress = 0
                        confettiPieces = []
                        onComplete()
                    }
                }
                .onDisappear {
                    dismissTask?.cancel()
                    dismissTask = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - Confetti

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let angle: CGFloat       // radians — direction of travel
    let distance: CGFloat    // final radial distance in points
    let rotation: Double     // spin amount in degrees
    let color: Color
    let size: CGFloat
    let shape: Shape

    enum Shape { case rect, circle, triangle }

    static func spawn(count: Int) -> [ConfettiPiece] {
        let palette: [Color] = [
            DailyOKColor.green400,
            DailyOKColor.green500,
            DailyOKColor.teal,
            DailyOKColor.gold,
            DailyOKColor.goldLight,
            DailyOKColor.indigo
        ]
        let shapes: [Shape] = [.rect, .circle, .triangle]
        return (0..<count).map { i in
            let baseAngle = (CGFloat(i) / CGFloat(count)) * (.pi * 2)
            let jitter = CGFloat.random(in: -0.25...0.25)
            return ConfettiPiece(
                angle: baseAngle + jitter,
                distance: CGFloat.random(in: 110...200),
                rotation: Double.random(in: 180...720) * (Bool.random() ? 1 : -1),
                color: palette[i % palette.count],
                size: CGFloat.random(in: 6...12),
                shape: shapes[i % shapes.count]
            )
        }
    }
}

private struct ConfettiLayer: View {
    let pieces: [ConfettiPiece]
    let progress: CGFloat    // 0 → 1 over the animation lifetime

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                let travelled = piece.distance * progress
                let gravity = (progress * progress) * 60   // slight drop as piece flies
                let offsetX = cos(piece.angle) * travelled
                let offsetY = sin(piece.angle) * travelled + gravity
                let fade = 1.0 - Double(progress) * 0.9

                confettiShape(for: piece)
                    .foregroundStyle(piece.color)
                    .frame(width: piece.size, height: piece.size)
                    .rotationEffect(.degrees(piece.rotation * Double(progress)))
                    .offset(x: offsetX, y: offsetY)
                    .opacity(fade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func confettiShape(for piece: ConfettiPiece) -> some View {
        switch piece.shape {
        case .rect:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
        case .circle:
            Circle()
        case .triangle:
            TrianglePath()
        }
    }
}

private struct TrianglePath: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
