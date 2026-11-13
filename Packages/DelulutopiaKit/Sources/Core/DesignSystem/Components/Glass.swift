import SwiftUI

public extension View {
    /// The system glass material behind this view (iOS 26+). The app never paints glass itself there
    /// (canvas "Glass over paper"). Before iOS 26 it falls back to a blurred, paper-tinted material
    /// with the canvas edge and shadow.
    @ViewBuilder
    func dlGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background { DLGlassFallback(shape: shape) }
        }
    }

    /// `dlGlass(in: Capsule())`.
    func dlGlassCapsule(interactive: Bool = false) -> some View {
        dlGlass(in: Capsule(), interactive: interactive)
    }
}

private struct DLGlassFallback<S: Shape>: View {
    let shape: S
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(DLPalette.glassTint.color))
            .overlay(shape.stroke(DLPalette.glassEdge.color, lineWidth: 0.5))
            .shadow(color: DLPalette.shade.color.opacity(scheme == .dark ? 0.45 : 0.13), radius: 15, y: 10)
    }
}

/// A round glass bar button (44 pt; back, ⋯, close) for places outside a navigation bar, such as
/// full-screen pads. Inside navigation bars use toolbar items: the system draws their glass.
public struct DLGlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    public init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.dlInk)
                .frame(width: 44, height: 44)
                .dlGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(DLPressStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}
