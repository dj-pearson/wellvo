import SwiftUI

/// A shimmer loading placeholder that matches the shape of real content.
struct SkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .overlay(
                Group {
                    if !reduceMotion {
                        // Branded shimmer highlight — soft brand green tint sweeping
                        // across the skeleton instead of plain neutral gray.
                        LinearGradient(
                            colors: [
                                Color(.systemGray5),
                                WellvoColor.green200.opacity(0.55),
                                Color(.systemGray5),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 100)
                        .offset(x: shimmerOffset)
                        .onAppear {
                            withAnimation(
                                .linear(duration: WellvoMotion.durationExtraLong * 2.5)
                                .repeatForever(autoreverses: false)
                            ) {
                                shimmerOffset = 400
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Skeleton that matches the layout of a ReceiverStatusCard on the Dashboard.
struct DashboardSkeletonView: View {
    var body: some View {
        LazyVStack(spacing: 16) {
            // Weekly summary skeleton
            VStack(alignment: .leading, spacing: 12) {
                SkeletonView(width: 140, height: 18)
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView(width: 60, height: 12)
                        SkeletonView(width: 40, height: 24)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView(width: 80, height: 12)
                        SkeletonView(width: 50, height: 24)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView(width: 70, height: 12)
                        SkeletonView(width: 30, height: 24)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Receiver card skeletons
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonView(width: 100, height: 16)
                            SkeletonView(width: 140, height: 12)
                        }
                        Spacer()
                        SkeletonView(width: 70, height: 28)
                    }
                    SkeletonView(height: 8)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .accessibilityLabel("Loading dashboard")
    }
}

/// Skeleton that matches the layout of the History calendar view.
struct HistorySkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Month header
            SkeletonView(width: 120, height: 20)

            // Calendar grid skeleton
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(0..<35, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 32)
                }
            }

            // Stats row
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 6) {
                        SkeletonView(width: 50, height: 12)
                        SkeletonView(width: 30, height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .padding()
        .accessibilityLabel("Loading history")
    }
}
