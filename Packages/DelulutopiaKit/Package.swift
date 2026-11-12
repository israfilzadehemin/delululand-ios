// swift-tools-version: 6.0
// Delulutopia's modules (decision D3, project doc "Delululand — iOS Build"). Core modules mirror the
// Android app's `core:*`; feature modules (`Feature/*`) arrive with the screens in PR #2.
import PackageDescription

let package = Package(
    name: "DelulutopiaKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DLDesignSystem", targets: ["DLDesignSystem"]),
        .library(name: "DLNetwork", targets: ["DLNetwork"]),
        .library(name: "DLData", targets: ["DLData"]),
        .library(name: "DLUI", targets: ["DLUI"]),
        .library(name: "FeatureStart", targets: ["FeatureStart"]),
        .library(name: "FeatureHome", targets: ["FeatureHome"]),
        .library(name: "FeatureLetters", targets: ["FeatureLetters"]),
        .library(name: "AppShell", targets: ["AppShell"]),
        // Linked only by the app-hosted screenshot target (DelulutopiaScreens).
        .library(name: "DLTestSupport", targets: ["DLTestSupport"]),
    ],
    dependencies: [
        // Test-only (decision D4): screenshot rendering for the parity loop.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    ],
    targets: [
        .target(
            name: "DLDesignSystem",
            path: "Sources/Core/DesignSystem",
            resources: [.copy("Resources/Fonts")]
        ),
        .target(
            name: "DLNetwork",
            path: "Sources/Core/Network"
        ),
        .target(
            name: "DLData",
            dependencies: ["DLNetwork"],
            path: "Sources/Core/Data"
        ),
        .target(
            name: "DLUI",
            dependencies: ["DLDesignSystem", "DLData", "DLNetwork"],
            path: "Sources/Core/UI"
        ),
        .target(
            name: "FeatureStart",
            dependencies: ["DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Start"
        ),
        .target(
            name: "FeatureHome",
            dependencies: ["DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Home"
        ),
        .target(
            name: "FeatureLetters",
            dependencies: ["DLDesignSystem", "DLData", "DLNetwork", "DLUI"],
            path: "Sources/Feature/Letters"
        ),
        .target(
            name: "AppShell",
            dependencies: ["DLDesignSystem", "DLData", "DLNetwork", "DLUI", "FeatureStart", "FeatureHome", "FeatureLetters"],
            path: "Sources/App/Shell"
        ),
        .target(
            name: "DLTestSupport",
            dependencies: [
                "DLDesignSystem",
                "DLData",
                "DLNetwork",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/Support",
            resources: [.copy("Media")]
        ),
        .testTarget(
            name: "DLDesignSystemTests",
            dependencies: ["DLDesignSystem"],
            path: "Tests/DesignSystem"
        ),
        .testTarget(
            name: "DLDataTests",
            dependencies: ["DLData", "DLNetwork"],
            path: "Tests/Data"
        ),
        .testTarget(
            name: "DLNetworkTests",
            dependencies: ["DLNetwork"],
            path: "Tests/Network"
        ),
        .testTarget(
            name: "AppShellTests",
            dependencies: ["AppShell", "DLData", "DLDesignSystem", "DLUI"],
            path: "Tests/AppShell"
        ),
    ]
)
