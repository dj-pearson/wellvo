// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wellvo",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "Wellvo",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
    ]
)
