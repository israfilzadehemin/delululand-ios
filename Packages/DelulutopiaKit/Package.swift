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
        .library(name: "DLData", targets: ["DLData"]),
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
            name: "DLData",
            path: "Sources/Core/Data"
        ),
        .target(
            name: "AppShell",
            dependencies: ["DLDesignSystem", "DLData"],
            path: "Sources/App/Shell"
        ),
        .target(
            name: "DLTestSupport",
            dependencies: [
                "DLDesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "DLDesignSystemTests",
            dependencies: ["DLDesignSystem"],
            path: "Tests/DesignSystem"
        ),
        .testTarget(
            name: "DLDataTests",
            dependencies: ["DLData"],
            path: "Tests/Data"
        ),
        .testTarget(
            name: "AppShellTests",
            dependencies: ["AppShell", "DLData", "DLDesignSystem"],
            path: "Tests/AppShell"
        ),
    ]
)
