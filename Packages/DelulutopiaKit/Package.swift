// swift-tools-version: 6.0
// Delulutopia's modules (decision D3, project doc "Delululand — iOS Build"). Core modules mirror the
// Android app's `core:*`; feature modules (`Feature/*`) arrive with the screens in PR #2.
import PackageDescription

let package = Package(
    name: "DelulutopiaKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DLI18n", targets: ["DLI18n"]),
        .library(name: "DLDesignSystem", targets: ["DLDesignSystem"]),
        .library(name: "DLNetwork", targets: ["DLNetwork"]),
        .library(name: "DLData", targets: ["DLData"]),
        .library(name: "DLUI", targets: ["DLUI"]),
        .library(name: "FeatureStart", targets: ["FeatureStart"]),
        .library(name: "FeatureHome", targets: ["FeatureHome"]),
        .library(name: "FeatureLetters", targets: ["FeatureLetters"]),
        .library(name: "FeatureDiscussions", targets: ["FeatureDiscussions"]),
        .library(name: "FeatureEmails", targets: ["FeatureEmails"]),
        .library(name: "AppShell", targets: ["AppShell"]),
        // Linked only by the app-hosted screenshot target (DelulutopiaScreens).
        .library(name: "DLTestSupport", targets: ["DLTestSupport"]),
    ],
    dependencies: [
        // Test-only (decision D4): screenshot rendering for the parity loop.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    ],
    targets: [
        // Languages (doc "Delululand — Languages"): the catalogue shared with the web and Android.
        .target(
            name: "DLI18n",
            path: "Sources/Core/I18n"
        ),
        .target(
            name: "DLDesignSystem",
            dependencies: ["DLI18n"],
            path: "Sources/Core/DesignSystem",
            resources: [.copy("Resources/Fonts")]
        ),
        .target(
            name: "DLNetwork",
            dependencies: ["DLI18n"],
            path: "Sources/Core/Network"
        ),
        .target(
            name: "DLData",
            dependencies: ["DLI18n", "DLNetwork"],
            path: "Sources/Core/Data"
        ),
        .target(
            name: "DLUI",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork"],
            path: "Sources/Core/UI"
        ),
        .target(
            name: "FeatureStart",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Start"
        ),
        .target(
            name: "FeatureHome",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Home"
        ),
        .target(
            name: "FeatureLetters",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Letters"
        ),
        .target(
            name: "FeatureDiscussions",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Discussions"
        ),
        .target(
            name: "FeatureEmails",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Emails"
        ),
        .target(
            name: "AppShell",
            dependencies: ["DLI18n", "DLDesignSystem", "DLData", "DLNetwork", "DLUI", "FeatureStart", "FeatureHome", "FeatureLetters", "FeatureDiscussions", "FeatureEmails"],
            path: "Sources/App/Shell"
        ),
        .target(
            name: "DLTestSupport",
            dependencies: [
                "DLI18n",
                "DLDesignSystem",
                "DLData",
                "DLNetwork",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/Support",
            resources: [.copy("Media")]
        ),
        .testTarget(
            name: "DLI18nTests",
            dependencies: ["DLI18n"],
            path: "Tests/I18n"
        ),
        .testTarget(
            name: "DLDesignSystemTests",
            dependencies: ["DLI18n", "DLDesignSystem"],
            path: "Tests/DesignSystem"
        ),
        .testTarget(
            name: "DLDataTests",
            dependencies: ["DLI18n", "DLData", "DLNetwork"],
            path: "Tests/Data"
        ),
        .testTarget(
            name: "DLNetworkTests",
            dependencies: ["DLI18n", "DLNetwork"],
            path: "Tests/Network"
        ),
        .testTarget(
            name: "AppShellTests",
            dependencies: ["DLI18n", "AppShell", "DLData", "DLDesignSystem", "DLUI"],
            path: "Tests/AppShell"
        ),
    ]
)
