// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyOK",
    platforms: [.iOS(.v18)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.0.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "DailyOK",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ]
        ),
        .testTarget(
            name: "DailyOKTests",
            dependencies: ["DailyOK"],
            path: "../DailyOKTests"
        ),
    ]
)
