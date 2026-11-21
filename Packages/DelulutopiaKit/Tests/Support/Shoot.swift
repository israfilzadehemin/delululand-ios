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
    public static func screen<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let traits = makeTraits(style)
        let image: Snapshotting<UIViewController, UIImage> = .image(
            drawHierarchyInKeyWindow: true, precision: 1, size: phone, traits: traits
        )
        record(
            host(view, style: style, topUpSafeArea: true),
            named: name,
            as: image,
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
            host(view, style: style, topUpSafeArea: false),
            named: name,
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

    /// Shoots `view` full screen after it has run in the key window for `wait` seconds, so its own
    /// loading (fixture API, images, stamps) lands first. The wait suspends the test, so the main
    /// actor keeps running the screen's tasks.
    public static func screen<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        wait: TimeInterval,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async {
        let controller = host(view, style: style, topUpSafeArea: true)
        if let window = keyWindow {
            window.rootViewController = controller
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
        }
        try? await Task.sleep(for: .seconds(wait))
        record(
            controller,
            named: name,
            as: .image(drawHierarchyInKeyWindow: true, precision: 1, size: phone, traits: makeTraits(style)),
            file: file,
            testName: testName,
            line: line
        )
    }

    /// True when the screenshot run is on an iPad simulator: the iPhone suites skip, the iPad suite
    /// runs (iPad Layout §7). Read from the simulator's environment, so traits can use it.
    nonisolated public static let onIPad: Bool = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]?.hasPrefix("iPad") ?? false
    /// True on the iPhone Duo simulator CI creates (iPad Layout IP12): only the Duo suite runs there.
    nonisolated public static let onDuo: Bool = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("Duo") ?? false

    /// Shoots `view` at the device's own size (the iPad run), turned to `landscape` first, after it
    /// has run in the key window for `wait` seconds.
    public static func device<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        wait: TimeInterval,
        landscape: Bool,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async {
        if let scene = keyWindow?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait)) { _ in }
            try? await Task.sleep(for: .seconds(1))
        }
        guard let window = keyWindow else { return }
        // An iPad app that supports multitasking cannot turn itself; if the window stayed upright,
        // the shot is laid out at the turned size inside it instead.
        var size = window.bounds.size
        if landscape != (size.width > size.height) {
            size = CGSize(width: size.height, height: size.width)
        }
        let controller = host(view, style: style, topUpSafeArea: false)
        window.rootViewController = controller
        controller.view.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        try? await Task.sleep(for: .seconds(wait))
        record(
            controller,
            named: name,
            as: .image(drawHierarchyInKeyWindow: true, precision: 1, size: size, traits: makeTraits(style)),
            file: file,
            testName: testName,
            line: line
        )
    }

    /// Shoots `view` at `size` with regular size classes, off screen (the iPhone Duo's inner display,
    /// iPad Layout IP12), after it has run for `wait` seconds.
    public static func sized<V: View>(
        _ view: V,
        named name: String,
        style: UIUserInterfaceStyle,
        size: CGSize,
        wait: TimeInterval,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async {
        let controller = host(view, style: style, topUpSafeArea: false)
        if let window = keyWindow {
            window.rootViewController = controller
            controller.view.frame = CGRect(origin: .zero, size: size)
            window.layoutIfNeeded()
        }
        try? await Task.sleep(for: .seconds(wait))
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.displayScale = 2
            traits.horizontalSizeClass = .regular
            traits.verticalSizeClass = .regular
        }
        let config = ViewImageConfig(safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0), size: size, traits: traits)
        record(controller, named: name, as: .image(on: config, precision: 1, traits: traits), file: file, testName: testName, line: line)
    }

    private static func host<V: View>(_ view: V, style: UIUserInterfaceStyle, topUpSafeArea: Bool) -> UIViewController {
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
        return host
    }

    private static func record(
        _ host: UIViewController,
        named name: String,
        as strategy: Snapshotting<UIViewController, UIImage>,
        file: StaticString,
        testName: String,
        line: UInt
    ) {
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
