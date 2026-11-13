import SwiftUI

/// A physical corner of a piece of paper. In Persian (L5) the text runs right to left but the paper is the
/// same paper: the stamp and postmark stay top right, the dog-ear bottom right, the board's corner and tray
/// where they are drawn (web `inset-inline` → physical `right`; Android `AbsoluteAlignment`).
public enum DLCorner: Sendable {
    case topRight, bottomRight, topLeft, bottomLeft

    /// The alignment that lands on this corner in `direction`.
    public func alignment(_ direction: LayoutDirection) -> Alignment {
        let rtl = direction == .rightToLeft
        return switch self {
        case .topRight: rtl ? .topLeading : .topTrailing
        case .bottomRight: rtl ? .bottomLeading : .bottomTrailing
        case .topLeft: rtl ? .topTrailing : .topLeading
        case .bottomLeft: rtl ? .bottomTrailing : .bottomLeading
        }
    }
}

public extension View {
    /// Draws `decoration` on a physical corner, laid out left to right as drawn.
    func overlay<Decoration: View>(on corner: DLCorner, @ViewBuilder _ decoration: () -> Decoration) -> some View {
        modifier(CornerOverlay(corner: corner, decoration: decoration()))
    }
}

private struct CornerOverlay<Decoration: View>: ViewModifier {
    @Environment(\.layoutDirection) private var direction
    let corner: DLCorner
    let decoration: Decoration

    func body(content: Content) -> some View {
        content.overlay(alignment: corner.alignment(direction)) {
            decoration.environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// A `ZStack` whose children sit on a physical corner (the board's corner mark, the tray's markers).
public struct DLCornerStack<Content: View>: View {
    @Environment(\.layoutDirection) private var direction
    let corner: DLCorner
    let content: Content

    public init(_ corner: DLCorner, @ViewBuilder content: () -> Content) {
        self.corner = corner
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: corner.alignment(direction)) { content }
    }
}
