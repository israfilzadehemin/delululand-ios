import SwiftUI

/// The web's enter keyframes (`motion.css`).
public enum DLEnter: Sendable {
    /// dl-fade-in: opacity only.
    case fade
    /// dl-rise: from 10 pt below.
    case rise
    /// dl-drop-in: from 8 pt above.
    case drop
    /// dl-pop-in: from 8 pt below at 96 %.
    case popIn
    /// dl-pop: 50 % → 112 % → 100 %, for chips and badges.
    case pop
    /// dl-zoom-in: from 94 %.
    case zoom
    /// dl-menu-in: a menu from its control, 92 %.
    case menu
    /// dl-paper-in: a letter sheet settling, from 18 pt below, tilted.
    case paper
    /// dl-stamp: a postmark struck at 170 %, rotated.
    case stamp

    var duration: Double {
        switch self {
        case .fade: 0.24
        case .pop: 0.46
        case .paper: 0.48
        case .stamp: 0.56
        case .menu: DLMotion.quickDuration
        case .zoom: 0.30
        default: 0.32
        }
    }

    /// Pop and stamp pass through a middle pose at this share of their duration.
    var midpoint: Double? {
        switch self {
        case .pop: 0.6
        case .stamp: 0.55
        default: nil
        }
    }
}

/// A pose of an entering element.
struct DLEnterPose: Equatable {
    var opacity: Double = 1
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1
    var rotation: Double = 0
    var anchor: UnitPoint = .center

    static var rest: DLEnterPose { DLEnterPose() }

    static func start(_ kind: DLEnter) -> DLEnterPose {
        switch kind {
        case .fade: DLEnterPose(opacity: 0)
        case .rise: DLEnterPose(opacity: 0, offsetY: 10)
        case .drop: DLEnterPose(opacity: 0, offsetY: -8)
        case .popIn: DLEnterPose(opacity: 0, offsetY: 8, scale: 0.96)
        case .pop: DLEnterPose(opacity: 0, scale: 0.5)
        case .zoom: DLEnterPose(opacity: 0, scale: 0.94)
        case .menu: DLEnterPose(opacity: 0, scale: 0.92)
        case .paper: DLEnterPose(opacity: 0, offsetY: 18, scale: 0.985, rotation: -0.6, anchor: .top)
        case .stamp: DLEnterPose(opacity: 0, scale: 1.7, rotation: -16)
        }
    }

    static func middle(_ kind: DLEnter) -> DLEnterPose {
        switch kind {
        case .pop: DLEnterPose(scale: 1.12)
        case .stamp: DLEnterPose(scale: 0.94, rotation: 2)
        default: .rest
        }
    }
}

private struct DLEnterModifier: ViewModifier {
    enum Phase { case start, middle, rest }

    let kind: DLEnter
    let delay: Double
    @State private var phase: Phase?
    @Environment(\.dlMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animated: Bool { motionEnabled && !reduceMotion }

    private var pose: DLEnterPose {
        guard animated else { return .rest }
        switch phase ?? .start {
        case .start: return .start(kind)
        case .middle: return .middle(kind)
        case .rest: return .rest
        }
    }

    func body(content: Content) -> some View {
        let pose = pose
        content
            .opacity(pose.opacity)
            .scaleEffect(pose.scale, anchor: pose.anchor)
            .rotationEffect(.degrees(pose.rotation), anchor: pose.anchor)
            .offset(y: pose.offsetY)
            .task {
                guard animated, phase == nil else { return }
                phase = .start
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                if let midpoint = kind.midpoint {
                    let first = kind.duration * midpoint
                    withAnimation(DLMotion.easeOut(first)) { phase = .middle }
                    try? await Task.sleep(for: .seconds(first))
                    withAnimation(DLMotion.easeOut(kind.duration - first)) { phase = .rest }
                } else {
                    let curve: Animation = kind == .fade
                        ? .linear(duration: kind.duration)
                        : DLMotion.easeOut(kind.duration)
                    withAnimation(curve) { phase = .rest }
                }
            }
    }
}

public extension View {
    /// Plays `kind` once, `delay` seconds after this element first appears (web enter keyframes).
    func dlEnter(_ kind: DLEnter = .rise, delay: Double = 0) -> some View {
        modifier(DLEnterModifier(kind: kind, delay: delay))
    }
}
