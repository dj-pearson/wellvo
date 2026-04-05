import SwiftUI

/// A branded progress view used as a small loading indicator matching the
/// Wellvo design system. Pulsing brand-green dot with a rotating arc.
///
/// SwiftUI's `.refreshable { }` modifier uses the system refresh control and
/// cannot be fully swapped out, but this view can be used anywhere else a
/// branded spinner is needed (inline loaders, empty-state loading, etc.)
/// and optionally layered on top of refresh regions for a premium feel.
struct BrandedProgressView: View {
    var size: CGFloat = 44
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 0.9

    var body: some View {
        ZStack {
            Circle()
                .fill(WellvoColor.green100)
                .frame(width: size, height: size)
                .scaleEffect(pulse)

            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    WellvoColor.brand,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size * 0.72, height: size * 0.72)
                .rotationEffect(.degrees(rotation))

            Circle()
                .fill(WellvoColor.brand)
                .frame(width: size * 0.28, height: size * 0.28)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = 1.1
            }
        }
    }
}
