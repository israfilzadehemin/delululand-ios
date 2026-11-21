import DLDesignSystem
import SwiftUI

/// The Board's (§9) and the selfie board's (DS1) fold. Folding, the open board rolls up from the
/// bottom into the strip while Home below rises with it, and the strip fades in as it lands;
/// unfolding, the strip fades out at once and the board unrolls downward. Android feature/home Fold.
enum Fold {
    static let duration = 0.36
    static var animation: Animation { DLMotion.easeOut(duration) }
}

extension AnyTransition {
    /// The open board: clipped from the bottom as it folds, revealed downward as it unfolds.
    static var dlFoldBoard: AnyTransition {
        .modifier(active: RollClip(progress: 0), identity: RollClip(progress: 1))
    }

    /// The folded strip: lands at the end of the roll, leaves at the start of the unroll.
    static var dlFoldStrip: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(DLMotion.easeOut(0.2).delay(Fold.duration - 0.16)),
            removal: .opacity.animation(DLMotion.easeOut(0.12))
        )
    }
}

/// Shows the top `progress` of its content; the mask reaches past the edges so shadows, pins and
/// tape stay whole when it is fully open. Fades over the last stretch so nothing lingers under
/// the strip.
private struct RollClip: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .mask(alignment: .top) {
                Rectangle().padding(-24).scaleEffect(x: 1, y: max(progress, 0.0001), anchor: .top)
            }
            .opacity(min(1, progress * 3))
    }
}
