import DLUI
import SwiftUI
import UIKit

// Bubble gestures that leave vertical scrolling to the thread (doc "Delululand — Bubble Actions"
// BA4; Email Replies RE6). Since iOS 18 a SwiftUI DragGesture or LongPressGesture on a ScrollView's
// content takes the touch, so a scroll that starts on a bubble never moves the list. On iOS 18+ the
// swipe and the long-press are UIKit recognizers instead: the pan begins only on a mostly sideways
// move, and the long-press recognizes alongside the scroll view's pan. iOS 17 keeps the SwiftUI ones.

/// RE6: a sideways pan; `translation` is in layout terms (positive = toward the trailing edge).
@available(iOS 18.0, *)
struct SidewaysPan: UIGestureRecognizerRepresentable {
    let rtl: Bool
    let onChanged: (CGFloat) -> Void
    /// `true` when the pan finished (finger up), `false` when the system cancelled it.
    let onEnded: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            let x = recognizer.translation(in: recognizer.view).x
            onChanged(rtl ? -x : x)
        case .ended:
            onEnded(true)
        case .cancelled, .failed:
            onEnded(false)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a mostly sideways start is a swipe; anything else is the scroll's.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }
}

/// BA4: a press held for ``BubbleActionsSpec/longPress`` that drifted less than the slop; the
/// scroll view keeps working alongside it. Once it fires, the touch no longer reaches the bubble's
/// buttons (a photo or the pill does not also open on release).
@available(iOS 18.0, *)
struct HoldPress: UIGestureRecognizerRepresentable {
    let onLong: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = BubbleActionsSpec.longPress
        press.allowableMovement = BubbleActionsSpec.slop
        press.delegate = context.coordinator
        return press
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { onLong() }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// iPad Layout IP8: a secondary click (right click, two-finger trackpad click) opens the same
/// actions as the long-press. Touches never match `buttonMaskRequired = .secondary`, so the iPhone
/// is untouched.
@available(iOS 18.0, *)
struct SecondaryClick: UIGestureRecognizerRepresentable {
    let onClick: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer()
        tap.buttonMaskRequired = .secondary
        // Taps on photos and pills inside the bubble must not wait for this one to fail.
        tap.delaysTouchesEnded = false
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        return tap
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { onClick() }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension View {
    /// The bubble's swipe-to-reply and long-press, scroll-friendly on every iOS version.
    @ViewBuilder
    func bubbleGestures(
        rtl: Bool,
        legacySwipe: some Gesture,
        onPan: @escaping (CGFloat) -> Void,
        onPanEnded: @escaping (Bool) -> Void,
        onLong: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            gesture(SidewaysPan(rtl: rtl, onChanged: onPan, onEnded: onPanEnded))
                .gesture(HoldPress(onLong: onLong))
                .gesture(SecondaryClick(onClick: onLong))
        } else {
            simultaneousGesture(legacySwipe)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: BubbleActionsSpec.longPress, maximumDistance: BubbleActionsSpec.slop)
                        .onEnded { _ in onLong() }
                )
        }
    }

    /// The pill's long-press (its tap is a Button), scroll-friendly on every iOS version.
    @ViewBuilder
    func holdToReact(_ onLong: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(HoldPress(onLong: onLong))
                .gesture(SecondaryClick(onClick: onLong))
        } else {
            simultaneousGesture(
                LongPressGesture(minimumDuration: BubbleActionsSpec.longPress, maximumDistance: BubbleActionsSpec.slop)
                    .onEnded { _ in onLong() }
            )
        }
    }
}
