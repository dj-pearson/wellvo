import SwiftUI

struct PaywallFeature: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let description: String
}

struct Testimonial: Identifiable {
    let id = UUID()
    let quote: String
    let author: String
}

/// Horizontal carousel showcasing premium features with animated page dots.
/// Designed to be embedded inside a paywall screen — parent provides the
/// feature list and the CTA button below it.
struct PaywallFeatureCarousel: View {
    let features: [PaywallFeature]
    @State private var currentIndex: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $currentIndex) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    PaywallFeatureCard(feature: feature)
                        .padding(.horizontal, 16)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)

            HStack(spacing: 8) {
                ForEach(0..<features.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? DailyOKColor.brand : Color(.systemGray4))
                        .frame(width: i == currentIndex ? 24 : 8, height: 8)
                        .animation(DailyOKMotion.smoothSpring, value: currentIndex)
                }
            }
        }
    }
}

private struct PaywallFeatureCard: View {
    let feature: PaywallFeature
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(scheme == .dark ? Color.white.opacity(0.14) : .white)
                    .frame(width: 80, height: 80)
                Image(systemName: feature.systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? DailyOKColor.green400 : DailyOKColor.green700)
            }

            Text(feature.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(scheme == .dark ? DailyOKColor.green400 : DailyOKColor.green700)

            Text(feature.description)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    // Light: pale green wash. Dark: a subtle green-tinted dark
                    // surface so the card doesn't stay bright against dark chrome.
                    colors: scheme == .dark
                        ? [DailyOKColor.green600.opacity(0.30), DailyOKColor.green700.opacity(0.16)]
                        : [DailyOKColor.green50, DailyOKColor.green100],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        )
    }
}

/// Animated "Save X%" badge for the annual plan.
struct AnnualSavingsBadge: View {
    let percentSaved: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("Save \(percentSaved)%")
            .font(.caption.weight(.bold))
            .foregroundStyle(scheme == .dark ? DailyOKColor.goldLight : DailyOKColor.gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(scheme == .dark ? DailyOKColor.gold.opacity(0.22) : DailyOKColor.goldLight)
            )
    }
}

/// A compact testimonial card for social proof.
struct TestimonialCard: View {
    let testimonial: Testimonial

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\u{201C}\(testimonial.quote)\u{201D}")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text("— \(testimonial.author)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
