import SwiftUI

struct OnboardingPageData: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let body: String
}

/// A swipeable onboarding carousel with animated dots and a primary CTA.
/// Host screens provide their own page list and a completion callback so
/// the component stays content-agnostic and reusable across the app.
struct OnboardingCarousel: View {
    let pages: [OnboardingPageData]
    var onComplete: () -> Void
    var onSkip: (() -> Void)? = nil
    var primaryCtaLabel: String = "Get Started"
    var nextLabel: String = "Next"
    var skipLabel: String = "Skip"

    @State private var currentIndex: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : DailyOKMotion.smoothSpring }

    var body: some View {
        // Guard against an empty page list: `pages.count - 1` below would be -1,
        // breaking the CTA logic and letting the index walk out of bounds
        // (US-IOS112).
        if pages.isEmpty {
            Color(.systemBackground)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if let onSkip, currentIndex < pages.count - 1 {
                    Button(skipLabel, action: onSkip)
                        .foregroundStyle(DailyOKColor.brand)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            // minHeight so a large "Skip" doesn't get clipped by the header row.
            .frame(minHeight: 44)

            TabView(selection: $currentIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(motion, value: currentIndex)

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? DailyOKColor.brand : Color(.systemGray4))
                        .frame(width: i == currentIndex ? 24 : 8, height: 8)
                        .animation(motion, value: currentIndex)
                }
            }
            .padding(.vertical, 16)
            // The dots are decorative; expose a single "Page X of N" element to
            // VoiceOver instead (US-IOS112).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(currentIndex + 1) of \(pages.count)")

            Button {
                if currentIndex == pages.count - 1 {
                    onComplete()
                } else {
                    withAnimation(motion) {
                        currentIndex += 1
                    }
                }
            } label: {
                Text(LocalizedStringKey(currentIndex == pages.count - 1 ? primaryCtaLabel : nextLabel))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    // The capsule grows with the label rather than cropping it.
                    .frame(minHeight: 52)
                    .background(
                        // White on the brand green500 was ~2.3:1.
                        Capsule().fill(DailyOKColor.green700)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPageData

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var circleSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 96 : 160 }

    var body: some View {
        // Scrolls at large text sizes instead of cutting the page off.
        ScrollView {
            pageContent
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private var pageContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green100)
                    .frame(width: circleSize, height: circleSize)
                Image(systemName: page.systemImage)
                    .font(.system(size: circleSize * 0.45, weight: .semibold))
                    .foregroundStyle(DailyOKColor.green700)
            }
            .accessibilityHidden(true)

            // LocalizedStringKey: Text(String) is never looked up in the
            // string catalog.
            Text(LocalizedStringKey(page.title))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey(page.body))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }
}
