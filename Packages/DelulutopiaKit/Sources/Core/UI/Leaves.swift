import DLData
import DLDesignSystem
import SwiftUI

/// Falling leaves (doc "Delululand — Falling Leaves"): decoration over the list screens (L1), above
/// content, never touchable (L7), off with Reduce Motion or Settings › Appearance › Seasonal effects
/// (L6). Each leaf's path is a closed form of time (flutter, drift, 3D flip), so the layer keeps no
/// state; a band of leaves lies at rest along the bottom, by the tab bar. Rich density (L3): 30
/// airborne in two depths (45 % contact size, 55 % front at 0.78×), 16 at rest.
public struct LeafLayer: View {
    @Environment(Backend.self) private var backend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dlMotionEnabled) private var motion
    @Environment(\.colorScheme) private var scheme

    public init() {}

    private static let palette: [(Double, Double, Double)] = [
        (0xD9, 0x9A, 0x82), (0xC4, 0x6A, 0x3C), (0xD8, 0xA2, 0x3E), (0xA9, 0x47, 0x2F), (0x9C, 0x9A, 0x55),
    ]
    private static let leaf = "M12 2C7 6 5 11 6.5 16c1 3 3.2 5 5.5 6 2.3-1 4.5-3 5.5-6C19 11 17 6 12 2z"

    public var body: some View {
        if backend.settings.leaves, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !motion)) { context in
                let t = motion ? context.date.timeIntervalSinceReferenceDate : 37
                Canvas { ctx, size in draw(&ctx, size: size, t: t) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
        }
    }

    private func color(_ i: Int, back: Bool) -> Color {
        let (r, g, b) = Self.palette[i % Self.palette.count]
        let dark = scheme == .dark
        // Dark: mixed 24 % toward the dark paper; back faces 28 % toward the paper.
        let paper: (Double, Double, Double) = dark ? (0x16, 0x18, 0x1F) : (0xF5, 0xF0, 0xE8)
        let k = (dark ? 0.24 : 0) + (back ? 0.28 : 0)
        return Color(red: (r + (paper.0 - r) * k) / 255, green: (g + (paper.1 - g) * k) / 255, blue: (b + (paper.2 - b) * k) / 255)
    }

    private func rand(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ salt &* 40503)
        x ^= x >> 13
        x &*= 0x5BD1E995
        x ^= x >> 15
        return Double(x % 10_000) / 10_000
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let path = PathData.path(Self.leaf)
        let vein = PathData.path("M12 4v18")
        // At rest along the bottom band (by the tab bar).
        for i in 0 ..< 16 {
            let x = size.width * (0.04 + 0.92 * rand(i, 7))
            let y = size.height - 30 - 34 * rand(i, 8)
            leafAt(&ctx, path: path, vein: vein, x: x, y: y, angle: (rand(i, 9) - 0.5) * 2.6 + .pi / 2, flip: 1, scale: 0.7, color: color(i, back: false), shadow: true)
        }
        // Airborne.
        for i in 0 ..< 30 {
            let front = rand(i, 1) > 0.45
            let scale = (front ? 0.78 : 1.0) * (0.85 + 0.3 * rand(i, 2))
            let fall = 34 + 26 * rand(i, 3)
            let span = size.height + 80
            let period = span / fall
            let phase = (t / period + rand(i, 4)).truncatingRemainder(dividingBy: 1)
            let y = -40 + phase * span
            let sway = 18 + 22 * rand(i, 5)
            let w = 0.9 + 0.8 * rand(i, 6)
            let gust = sin(t * 0.13 + Double(i)) * 24
            let x = size.width * rand(i, 10) + sin(t * w + Double(i) * 1.7) * sway + gust + phase * 30
            let angle = sin(t * w * 0.9 + Double(i)) * 0.9 + rand(i, 11) * 6
            let flip = cos(t * (0.6 + rand(i, 12)) + Double(i))
            leafAt(&ctx, path: path, vein: vein, x: x, y: y, angle: angle, flip: flip, scale: scale, color: color(i, back: flip < 0), shadow: false)
        }
    }

    private func leafAt(_ ctx: inout GraphicsContext, path: Path, vein: Path, x: Double, y: Double, angle: Double, flip: Double, scale: Double, color: Color, shadow: Bool) {
        var c = ctx
        c.translateBy(x: x, y: y)
        c.rotate(by: .radians(angle))
        c.scaleBy(x: max(0.15, abs(flip)) * scale * 0.75, y: scale * 0.75)
        c.translateBy(x: -12, y: -12)
        c.opacity = 0.92
        if shadow {
            var s = c
            s.translateBy(x: 1.2, y: 1.6)
            s.fill(path, with: .color(.black.opacity(scheme == .dark ? 0.35 : 0.16)))
        }
        c.fill(path, with: .color(color))
        c.stroke(vein, with: .color(.black.opacity(0.18)), lineWidth: 1)
    }
}
