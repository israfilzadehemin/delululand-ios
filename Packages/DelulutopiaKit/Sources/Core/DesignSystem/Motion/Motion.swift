import SwiftUI

/// Motion tokens (web `src/styles/motion.css`, doc "Delululand — Motion"; Android `Motion`). Enter
/// animations play once when an element first appears, presses scale, a few marks loop. Only opacity
/// and transforms move. With Reduce Motion on (or in screenshot tests) every element is simply shown.
public enum DLMotion {
    public static let pressDuration: Double = 0.12
    public static let quickDuration: Double = 0.16
    public static let enterDuration: Double = 0.28
    public static let pageDuration: Double = 0.30

    /// `--dl-ease-out`: cubic-bezier(0.2, 0.8, 0.2, 1).
    public static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
    }

    /// `--dl-ease-in`: cubic-bezier(0.4, 0, 1, 1).
    public static func easeIn(_ duration: Double) -> Animation {
        .timingCurve(0.4, 0, 1, 1, duration: duration)
    }

    /// `--dl-spring`: cubic-bezier(0.34, 1.56, 0.64, 1), a small overshoot.
    public static func spring(_ duration: Double) -> Animation {
        .timingCurve(0.34, 1.56, 0.64, 1, duration: duration)
    }

    /// The web's list stagger: 40 ms a row, the ninth and later all at 320 ms.
    public static func stagger(_ index: Int, step: Double = 0.04, cap: Double = 0.32) -> Double {
        min(Double(max(index, 0)) * step, cap)
    }
}

private struct DLMotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// False draws the static design (screenshot tests). Reduce Motion is honoured on its own.
    var dlMotionEnabled: Bool {
        get { self[DLMotionEnabledKey.self] }
        set { self[DLMotionEnabledKey.self] = newValue }
    }
}

/// Pressed controls shrink a little (web `:active`: buttons 0.97, keys 0.9, rows 0.985).
public struct DLPressStyle: ButtonStyle {
    public let scale: CGFloat

    public init(scale: CGFloat = 0.97) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        DLPressBody(configuration: configuration, scale: scale)
    }
}

private struct DLPressBody: View {
    let configuration: ButtonStyle.Configuration
    let scale: CGFloat
    @Environment(\.dlMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = motionEnabled && !reduceMotion
        configuration.label
            .scaleEffect(animate && configuration.isPressed ? scale : 1)
            .animation(DLMotion.easeOut(DLMotion.pressDuration), value: configuration.isPressed)
    }
}
