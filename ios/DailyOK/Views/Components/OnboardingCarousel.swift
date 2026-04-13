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

    var body: some View {
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
            .frame(height: 44)

            TabView(selection: $currentIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(DailyOKMotion.smoothSpring, value: currentIndex)

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? DailyOKColor.brand : Color(.systemGray4))
                        .frame(width: i == currentIndex ? 24 : 8, height: 8)
                        .animation(DailyOKMotion.smoothSpring, value: currentIndex)
                }
            }
            .padding(.vertical, 16)

            Button {
                if currentIndex == pages.count - 1 {
                    onComplete()
                } else {
                    withAnimation(DailyOKMotion.smoothSpring) {
                        currentIndex += 1
                    }
                }
            } label: {
                Text(currentIndex == pages.count - 1 ? primaryCtaLabel : nextLabel)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule().fill(DailyOKColor.brand)
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

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green100)
                    .frame(width: 160, height: 160)
                Image(systemName: page.systemImage)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(DailyOKColor.green700)
            }
            .accessibilityHidden(true)

            Text(page.title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(page.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }
}
