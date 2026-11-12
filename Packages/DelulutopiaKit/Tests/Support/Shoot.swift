import DLDesignSystem
import Foundation
import SnapshotTesting
import SwiftUI
import UIKit

/// Renders screens to PNGs for review (the Android `ParityScreensTest` / Roborazzi twin, decision D5).
/// CI sets `DL_SNAPSHOT_DIR` (through `TEST_RUNNER_DL_SNAPSHOT_DIR`) and publishes the files to the
/// `ci-screenshots` branch. The shots are review material, not a pass/fail gate: a run records them
/// and never fails on a difference.
///
/// Runs in the app-hosted `DelulutopiaScreens` target: `screen` draws through the host app's key
/// window, so system materials (Liquid Glass bars, toggles) look as they do on a device. `page` draws
/// taller-than-screen pages off screen, where system glass does not render.
@MainActor
public enum Shoot {
    /// iPhone 17 Pro in points (iOS design I2), with its status bar and home indicator insets.
    public static let phone = CGSize(width: 402, height: 874)
    public static let phoneSafeArea = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)

    public static var outputDirectory: String {
        if let dir = ProcessInfo.processInfo.environment["DL_SNAPSHOT_DIR"], !dir.isEmpty {
            return dir
        }
        return NSTemporaryDirectory() + "dl-snapshots"
    }

    /// Shoots `view` full screen in the host app's key window with the given appearance and writes
    /// `<name>.png`.
    /// `wait` lets the screen's own loading (fixture API, images, stamps) finish before the capture.
    public static func screen<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        wait: TimeInterval = 0,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let traits = makeTraits(style)
        let image: Snapshotting<UIViewController, UIImage> = .image(
            drawHierarchyInKeyWindow: true, precision: 1, size: phone, traits: traits
        )
        record(
            view,
            named: name,
            style: style,
            topUpSafeArea: true,
            as: wait > 0 ? .wait(for: wait, on: image) : image,
            file: file,
            testName: testName,
            line: line
        )
    }

    /// A tall page drawn off screen (component catalog), safe area zero.
    public static func page<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        height: CGFloat,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let traits = makeTraits(style)
        let config = ViewImageConfig(safeArea: .zero, size: CGSize(width: phone.width, height: height), traits: traits)
        record(
            view,
            named: name,
            style: style,
            topUpSafeArea: false,
            as: .image(on: config, precision: 1, traits: traits),
            file: file,
            testName: testName,
            line: line
        )
    }

    private static func makeTraits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.displayScale = 2
        }
    }

    private static func record<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        topUpSafeArea: Bool,
        as strategy: Snapshotting<UIViewController, UIImage>,
        file: StaticString,
        testName: String,
        line: UInt
    ) {
        DLFonts.register()
        DLAppearance.apply()
        let host = UIHostingController(rootView: view.environment(\.dlMotionEnabled, false))
        host.overrideUserInterfaceStyle = style
        if topUpSafeArea {
            // The resized key window can report smaller insets than a device; add the difference so
            // bars and titles sit where they do on an iPhone.
            let actual = keyWindow?.safeAreaInsets ?? .zero
            host.additionalSafeAreaInsets = UIEdgeInsets(
                top: max(0, phoneSafeArea.top - actual.top),
                left: 0,
                bottom: max(0, phoneSafeArea.bottom - actual.bottom),
                right: 0
            )
        }
        let directory = outputDirectory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        withSnapshotTesting(record: .all) {
            _ = verifySnapshot(
                of: host,
                as: strategy,
                named: name,
                snapshotDirectory: directory,
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
