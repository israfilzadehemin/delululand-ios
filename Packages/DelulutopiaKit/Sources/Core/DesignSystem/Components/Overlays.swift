import SwiftUI

/// The PIN progress dots: 14 pt, 16 pt apart; entered = seal, empty = 1.5 pt quiet ring.
public struct DLPinDots: View {
    let length: Int
    let entered: Int
    let error: Bool

    public init(length: Int = 6, entered: Int, error: Bool = false) {
        self.length = length
        self.entered = entered
        self.error = error
    }

    public var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<length, id: \.self) { index in
                if index < entered {
                    Circle()
                        .fill(error ? Color.dlError : Color.dlSeal)
                        .frame(width: 14, height: 14)
                } else {
                    Circle()
                        .strokeBorder(error ? Color.dlError : Color.dlInkQuiet, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN, \(entered) of \(length) digits entered")
    }
}

/// A glass toast capsule above the tab bar (replaces Android snackbars): a symbol, a line of text and
/// an optional action ("Undo", "Settings").
public struct DLToast: View {
    let symbol: String?
    let text: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(_ text: String, symbol: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.dlInk)
            }
            Text(text)
                .dlText(.subheadline)
                .foregroundStyle(.dlInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.dlText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .dlGlassCapsule()
        .accessibilityElement(children: .contain)
    }
}

/// The "Continue your letter" capsule (iOS design I3): a seal circle with the compose symbol, the
/// label, a navy dot and a chevron. On iOS 26+ it is the content of `tabViewBottomAccessory`, which
/// draws the glass; pass `glass: true` where the app hosts it itself.
public struct DLDraftAccessory: View {
    let title: String
    let symbol: String
    let glass: Bool
    let action: () -> Void

    public init(_ title: String, symbol: String = "square.and.pencil", glass: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.glass = glass
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.dlOnSeal)
                    .frame(width: 30, height: 30)
                    .background(.dlSeal, in: Circle())
                Text(title)
                    .dlText(.subheadlineBold)
                    .foregroundStyle(.dlInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .fill(.dlSeal)
                    .frame(width: 7, height: 7)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.dlInkQuiet)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .modifier(DLOptionalGlass(enabled: glass))
            .contentShape(Capsule())
        }
        .buttonStyle(DLPressStyle(scale: 0.98))
    }
}

private struct DLOptionalGlass: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.dlGlassCapsule(interactive: true)
        } else {
            content
        }
    }
}
