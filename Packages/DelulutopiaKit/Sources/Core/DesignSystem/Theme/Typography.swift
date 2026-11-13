import SwiftUI
import UIKit

/// The system text style a brand style scales with (Dynamic Type, iOS design rule I-9).
public enum DLScaleBase: Sendable {
    case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption, caption2

    public var swiftUI: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }

    public var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        }
    }
}

/// One brand text style: face, size and line height in pt at the default (Large) setting, tracking
/// in em (CSS `letter-spacing`).
public struct DLTextSpec: Sendable {
    /// Nil is the system monospaced face (entry keys).
    public let face: DLFontName?
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let trackingEm: CGFloat
    public let base: DLScaleBase
    public let uppercase: Bool
    public let tabularDigits: Bool

    public init(
        _ face: DLFontName?,
        _ size: CGFloat,
        _ lineHeight: CGFloat,
        tracking: CGFloat = 0,
        base: DLScaleBase,
        uppercase: Bool = false,
        tabularDigits: Bool = false
    ) {
        self.face = face
        self.size = size
        self.lineHeight = lineHeight
        self.trackingEm = tracking
        self.base = base
        self.uppercase = uppercase
        self.tabularDigits = tabularDigits
    }

    /// The face at an exact size (already scaled).
    public func font(fixedSize size: CGFloat) -> Font {
        let font: Font = if let face {
            .custom(face.name, fixedSize: size)
        } else {
            .system(size: size, weight: .regular, design: .monospaced)
        }
        return tabularDigits ? font.monospacedDigit() : font
    }

    /// The face scaling with Dynamic Type, for places that only take a `Font`.
    public var dynamicFont: Font {
        let font: Font = if let face {
            .custom(face.name, size: size, relativeTo: base.swiftUI)
        } else {
            .system(base.swiftUI, design: .monospaced)
        }
        return tabularDigits ? font.monospacedDigit() : font
    }

    /// The UIKit font, scaled for the current content size (navigation bar titles).
    public func uiFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let base = uiFontUnscaled(size: size)
        return UIFontMetrics(forTextStyle: self.base.uiKit).scaledFont(for: base, compatibleWith: traits)
    }

    func uiFontUnscaled(size: CGFloat) -> UIFont {
        if let face, let font = UIFont(name: face.name, size: size) {
            return font
        }
        return face == nil ? .monospacedSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size)
    }

    /// Extra space between lines that turns the face's natural line height into the design's.
    func lineSpacing(atSize scaledSize: CGFloat) -> CGFloat {
        let factor = scaledSize / size
        let natural = uiFontUnscaled(size: scaledSize).lineHeight
        return max(0, lineHeight * factor - natural)
    }
}

/// The type ramp (iOS canvas "Foundations › Type", plus the brand styles the web and Android use).
public enum DLTextStyle: String, CaseIterable, Sendable {
    /// Manrope ExtraBold 34/41 — tab-root large titles.
    case largeTitle
    /// Literata SemiBold 28/34 — the universe name.
    case title1
    /// Manrope ExtraBold 22/28 — "Enter your PIN".
    case title2
    /// Manrope ExtraBold 20/25.
    case title3
    /// Manrope ExtraBold 17/22 — inline titles, "To Leyla".
    case headline
    /// Manrope Medium 17/22.
    case body
    /// Manrope Medium 16/21 — grouped-list rows.
    case callout
    /// Manrope SemiBold 15/20 — "Arrives 15:20", toasts.
    case subheadline
    /// Manrope Bold 15/20 — the "Continue your …" accessory.
    case subheadlineBold
    /// Manrope Medium 13/18 — times, hints.
    case footnote
    /// Manrope SemiBold 13/18 — field errors.
    case footnoteStrong
    /// Manrope Bold 13/18 — field labels.
    case fieldLabel
    /// Manrope ExtraBold 11/13, +0.08 em, caps — section labels ("FROM LEYLA").
    case label
    /// Manrope ExtraBold 11/14, +0.08 em, caps — NEW / SOON pills.
    case pill
    /// Manrope Bold 18/24, tabular digits — countdowns (28:41).
    case countdown
    /// Manrope ExtraBold 16/20 — filled and grey buttons.
    case button
    /// Manrope ExtraBold 14/18 — outline and tint buttons.
    case buttonSmall
    /// Manrope Regular 17/22 — text fields.
    case input
    /// System monospaced 18/22, +0.08 em — entry keys (XXXX-XXXX-XXXX).
    case key
    /// Literata Regular 17/28 — the letter body on its 28 pt rules.
    case letterBody
    /// Literata SemiBold 22/28 — discussion note titles.
    case noteTitle
    /// Caveat Medium 21/22 — the board note.
    case handwriting

    public var spec: DLTextSpec {
        switch self {
        case .largeTitle: DLTextSpec(.manropeExtraBold, 34, 41, base: .largeTitle)
        case .title1: DLTextSpec(.literataSemiBold, 28, 34, base: .title)
        case .title2: DLTextSpec(.manropeExtraBold, 22, 28, base: .title2)
        case .title3: DLTextSpec(.manropeExtraBold, 20, 25, base: .title3)
        case .headline: DLTextSpec(.manropeExtraBold, 17, 22, base: .headline)
        case .body: DLTextSpec(.manropeMedium, 17, 22, base: .body)
        case .callout: DLTextSpec(.manropeMedium, 16, 21, base: .callout)
        case .subheadline: DLTextSpec(.manropeSemiBold, 15, 20, base: .subheadline)
        case .subheadlineBold: DLTextSpec(.manropeBold, 15, 20, base: .subheadline)
        case .footnote: DLTextSpec(.manropeMedium, 13, 18, base: .footnote)
        case .footnoteStrong: DLTextSpec(.manropeSemiBold, 13, 18, base: .footnote)
        case .fieldLabel: DLTextSpec(.manropeBold, 13, 18, base: .footnote)
        case .label: DLTextSpec(.manropeExtraBold, 11, 13, tracking: 0.08, base: .caption2, uppercase: true)
        case .pill: DLTextSpec(.manropeExtraBold, 11, 14, tracking: 0.08, base: .caption2, uppercase: true)
        case .countdown: DLTextSpec(.manropeBold, 18, 24, base: .headline, tabularDigits: true)
        case .button: DLTextSpec(.manropeExtraBold, 16, 20, tracking: 0.005, base: .headline)
        case .buttonSmall: DLTextSpec(.manropeExtraBold, 14, 18, tracking: 0.005, base: .subheadline)
        case .input: DLTextSpec(.manropeRegular, 17, 22, base: .body)
        case .key: DLTextSpec(nil, 18, 22, tracking: 0.08, base: .body)
        case .letterBody: DLTextSpec(.literataRegular, 17, 28, base: .body)
        case .noteTitle: DLTextSpec(.literataSemiBold, 22, 28, base: .title2)
        case .handwriting: DLTextSpec(.caveatMedium, 21, 22, base: .body)
        }
    }
}

/// Applies a brand text style: face, Dynamic Type size, line height and tracking all scale together.
struct DLTextModifier: ViewModifier {
    private let spec: DLTextSpec
    @ScaledMetric private var size: CGFloat

    init(_ style: DLTextStyle) {
        let spec = style.spec
        self.spec = spec
        _size = ScaledMetric(wrappedValue: spec.size, relativeTo: spec.base.swiftUI)
    }

    func body(content: Content) -> some View {
        content
            .font(spec.font(fixedSize: size))
            .lineSpacing(spec.lineSpacing(atSize: size))
            .tracking(spec.trackingEm * size)
            .textCase(spec.uppercase ? .uppercase : nil)
    }
}

public extension View {
    /// Sets a brand text style (`Text("Letters").dlText(.largeTitle)`).
    func dlText(_ style: DLTextStyle) -> some View {
        modifier(DLTextModifier(style))
    }
}
