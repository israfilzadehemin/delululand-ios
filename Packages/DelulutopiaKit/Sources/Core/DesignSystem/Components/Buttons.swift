import SwiftUI

/// Capsule buttons (canvas Components; web `.dl-btn`).
public struct DLButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        /// Seal fill, 50 pt: "Write a letter", "Send".
        case filled
        /// System grey fill, 50 pt: "Keep writing".
        case grey
        /// 1.5 pt seal ring, 40 pt: "Edit".
        case outline
        /// Lavender fill, 34 pt: "Allow".
        case tint
        /// Error fill, 50 pt.
        case danger
        /// Seal text only.
        case text
    }

    public let kind: Kind
    public let fullWidth: Bool

    public init(_ kind: Kind, fullWidth: Bool = false) {
        self.kind = kind
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        DLButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

public extension ButtonStyle where Self == DLButtonStyle {
    static var dlFilled: DLButtonStyle { DLButtonStyle(.filled) }
    static var dlGrey: DLButtonStyle { DLButtonStyle(.grey) }
    static var dlOutline: DLButtonStyle { DLButtonStyle(.outline) }
    static var dlTint: DLButtonStyle { DLButtonStyle(.tint) }
    static var dlDanger: DLButtonStyle { DLButtonStyle(.danger) }
    static var dlText: DLButtonStyle { DLButtonStyle(.text) }
}

private struct DLButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: DLButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dlMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat {
        switch kind {
        case .filled, .grey, .danger: 50
        case .outline: 40
        case .tint: 34
        case .text: 44
        }
    }

    private var foreground: Color {
        guard isEnabled else { return kind == .text ? .dlInkDisabled : .dlInkQuiet }
        switch kind {
        case .filled, .danger: return .dlOnSeal
        case .grey: return .dlInk
        case .outline, .tint, .text: return .dlSeal
        }
    }

    private var fill: Color {
        switch kind {
        case .filled: isEnabled ? .dlSeal : .dlLine
        case .grey: .dlSystemFill
        case .danger: isEnabled ? .dlError : .dlLine
        case .tint: .dlSealTint
        case .outline, .text: .clear
        }
    }

    var body: some View {
        let pressed = configuration.isPressed && motionEnabled && !reduceMotion
        configuration.label
            .labelStyle(DLButtonLabelStyle())
            .dlText(kind == .outline || kind == .tint ? .buttonSmall : .button)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .text ? 8 : 22)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(fill, in: Capsule())
            .overlay {
                if kind == .outline {
                    Capsule().strokeBorder(foreground, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed && kind == .text ? 0.6 : 1)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(DLMotion.easeOut(DLMotion.pressDuration), value: configuration.isPressed)
    }
}

/// Icon and title 8 pt apart, the icon at 19 pt (canvas "Write a letter").
private struct DLButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 17, weight: .semibold))
            configuration.title
        }
    }
}
