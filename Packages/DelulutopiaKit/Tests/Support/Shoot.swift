import DLDesignSystem
import Foundation
import SnapshotTesting
import SwiftUI
import UIKit

/// Renders screens to PNGs for review (the Android `ParityScreensTest` / Roborazzi twin, decision D5).
/// CI sets `DL_SNAPSHOT_DIR` (through `TEST_RUNNER_DL_SNAPSHOT_DIR`) and publishes the files to the
/// `ci-screenshots` branch. The shots are review material, not a pass/fail gate: a run records them
/// and never fails on a difference.
@MainActor
public enum Shoot {
    /// iPhone 17 Pro in points (iOS design I2): 402 × 874, status bar 62, home indicator 34.
    public static let phone = CGSize(width: 402, height: 874)
    public static let phoneSafeArea = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)

    public static var outputDirectory: String {
        if let dir = ProcessInfo.processInfo.environment["DL_SNAPSHOT_DIR"], !dir.isEmpty {
            return dir
        }
        return NSTemporaryDirectory() + "dl-snapshots"
    }

    /// Shoots `view` in a window of `size` with the given appearance and writes `<name>.png`.
    public static func screen<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        size: CGSize = phone,
        safeArea: UIEdgeInsets = phoneSafeArea,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        DLFonts.register()
        DLAppearance.apply()
        let host = UIHostingController(rootView: view.environment(\.dlMotionEnabled, false))
        host.overrideUserInterfaceStyle = style
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.displayScale = 2
        }
        let config = ViewImageConfig(safeArea: safeArea, size: size, traits: traits)
        let directory = outputDirectory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        withSnapshotTesting(record: .all) {
            _ = verifySnapshot(
                of: host,
                as: .image(on: config, precision: 1, traits: traits),
                named: name,
                snapshotDirectory: directory,
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    /// A tall canvas for scrolling pages such as the component catalog.
    public static func page<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        height: CGFloat,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        screen(
            view,
            named: name,
            style: style,
            size: CGSize(width: phone.width, height: height),
            safeArea: .zero,
            file: file,
            testName: testName,
            line: line
        )
    }
}
