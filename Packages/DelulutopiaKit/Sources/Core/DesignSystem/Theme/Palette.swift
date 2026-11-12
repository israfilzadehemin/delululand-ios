import SwiftUI
import UIKit

/// Colour roles, one-to-one with delululand-web `src/styles/tokens.css` (+ `materials.css`,
/// `board/board.css`) and the iOS canvas "Foundations › Colour roles". Names follow the web tokens,
/// so a colour change is made once per platform. Values are light / dark.
public enum DLPalette {
    // MARK: Surfaces
    /// `--dl-paper`: the page (systemBackground).
    public static let paper = DLColorToken(0xF5F0E8, 0x16181F)
    /// `--dl-paper-letter`: rows, cards, the letter surface.
    public static let paperLetter = DLColorToken(0xE8E1D8, 0x22252E)
    /// `--dl-paper-deep`: the reference panel (same as rows in palette rev 2).
    public static let paperDeep = DLColorToken(0xE8E1D8, 0x22252E)
    /// iOS grouped cell (secondarySystemGroupedBackground role).
    public static let cell = DLColorToken(0xFCFAF6, 0x22252E)
    /// iOS sheet background.
    public static let sheet = DLColorToken(0xF7F3EC, 0x1C1F27)
    /// `--dl-line`: borders, dividers (separator).
    public static let line = DLColorToken(0xD9D0C5, 0x3B3F4C)
    /// `--dl-placeholder`: loading placeholders.
    public static let placeholder = DLColorToken(0xD9D0C5, 0x3B3F4C)

    // MARK: Ink
    /// `--dl-ink`: text and icons (label).
    public static let ink = DLColorToken(0x33323B, 0xECE6DC)
    /// `--dl-ink-quiet`: times, hints, section labels (secondary label).
    public static let inkQuiet = DLColorToken(0x48536C, 0xA3ADC4)
    /// `--dl-ink-disabled`: disabled controls (non-text use only).
    public static let inkDisabled = DLColorToken(0xA3A8B6, 0x5C6273)
    /// `--dl-ink-on-scrim`: disabled controls on the lightbox / scrim.
    public static let inkOnScrim = DLColorToken(same: 0x7A8296)

    // MARK: Seal (the one accent)
    /// `--dl-seal`: tint / accentColor.
    public static let seal = DLColorToken(0x202B45, 0xB4C2EA)
    /// `--dl-seal-hue`: arc fill and other non-text accents (terracotta).
    public static let sealHue = DLColorToken(same: 0xD99A82)
    /// `--dl-seal-tint`: selected chip, in-reach card (lavender).
    public static let sealTint = DLColorToken(0xE4DFF0, 0x2C2A40)
    public static let sealTintLine = DLColorToken(0xC9BFE0, 0x4B4670)
    /// `--dl-seal-dark`: pressed / hover.
    public static let sealDark = DLColorToken(0x48536C, 0xA3ADC4)
    /// `--dl-on-seal`: text and icons on seal fills.
    public static let onSeal = DLColorToken(0xFFFFFF, 0x141A2C)

    // MARK: Postmark
    public static let postmark = DLColorToken(0x48536C, 0xA3ADC4)
    public static let postmarkHue = DLColorToken(0x6F978B, 0x7FA89B)

    // MARK: Signature colours
    /// `--dl-user-a`: the universe creator's ring and arc (terracotta).
    public static let userA = DLColorToken(same: 0xD99A82)
    public static let userAText = DLColorToken(0x202B45, 0xB4C2EA)
    public static let userATint = DLColorToken(0xF2E0D7, 0x3B2A24)
    /// `--dl-user-b`: the other citizen's ring (sage).
    public static let userB = DLColorToken(same: 0x9CBDB3)
    public static let userBText = DLColorToken(0x48536C, 0xA3ADC4)
    public static let userBTint = DLColorToken(0xDCE8E3, 0x1F2D2A)

    // MARK: Status
    /// `--dl-error`: destructive in app content (alerts and menus use systemRed).
    public static let error = DLColorToken(0xB23A3A, 0xEE8A80)
    public static let errorTint = DLColorToken(0xF3DADA, 0x3A2224)
    public static let errorLine = DLColorToken(0xE2B5B5, 0x6B3436)
    /// `--dl-scrim`.
    public static let scrim = DLColorToken(0x202B45, 0x000000, lightAlpha: 0.45, darkAlpha: 0.6)
    /// `--dl-shade-rgb`: navy ink (light) / black (dark) for shadows.
    public static let shade = DLColorToken(0x202B45, 0x000000)
    public static let lightbox = DLColorToken(0x202B45, 0x0B0D12)
    public static let onLightbox = DLColorToken(same: 0xF5F0E8)
    public static let onLightboxQuiet = DLColorToken(same: 0xD9D0C5)

    // MARK: Glass (fallback before iOS 26; canvas "Glass over paper")
    public static let glassTint = DLColorToken(0xFBF9F5, 0x262933, lightAlpha: 0.66, darkAlpha: 0.62)
    public static let glassEdge = DLColorToken(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.85, darkAlpha: 0.14)

    // MARK: Letters (envelope, sheet, slip)
    public static let letterSheet = DLColorToken(0xFBF8F3, 0x3A3630)
    public static let letterEnvelope = DLColorToken(0xE8E1D8, 0x332F2A)
    public static let letterFlap = DLColorToken(0xDED5C9, 0x2B2823)
    public static let letterEdge = DLColorToken(0xC9BFB2, 0x4B463E)
    public static let letterSlip = DLColorToken(0xFFFDF9, 0x444039)
    public static let letterInk = DLColorToken(0x33323B, 0xE8E0D2)
    public static let letterRule = DLColorToken(0x48536C, 0xE8E0D2, lightAlpha: 0.16, darkAlpha: 0.09)
    public static let letterMargin = DLColorToken(0xB23A3A, 0xEE8A80, lightAlpha: 0.22, darkAlpha: 0.3)
    public static let letterPrint = DLColorToken(0xFFFFFF, 0xD9D1C2)
    public static let letterTape = DLColorToken(0xF0E8D2, 0xD6CCB0, lightAlpha: 0.78, darkAlpha: 0.35)

    // MARK: Letter status marks
    public static let markContainer = DLColorToken(0xF2D9C8, 0x55402F)
    public static let markLine = DLColorToken(0xDFAE92, 0x7D5C46)
    public static let countdownChip = DLColorToken(0xE6C3AD, 0x6A503D)
    public static let newBadge = DLColorToken(0xA9512F, 0xE3A184)
    public static let onNewBadge = DLColorToken(0xFFF8F2, 0x2B1A12)
    public static let reactLine = DLColorToken(0xC98B6E, 0xC4785A)

    // MARK: Mail cards (Emails)
    public static let mailBackground = DLColorToken(0xFFFFFF, 0x23262E)
    public static let mailMine = DLColorToken(0xF3F5F9, 0x2A2E37)
    public static let mailLine = DLColorToken(0xDDE2EA, 0x353A46)
    public static let mailBlue = DLColorToken(0x2A62CC, 0x8AB4FF)
    public static let onMailBlue = DLColorToken(0xFFFFFF, 0x0F1A2E)
    public static let mailUnread = DLColorToken(0xEEF3FD, 0x262C3A)
    public static let mailInk = DLColorToken(0x1F2430, 0xE6E9EF)

    // MARK: Board (whiteboard)
    public static let boardFrame = DLColorToken(0xC7CBD1, 0x4B4F57)
    public static let boardTray = DLColorToken(0xAEB3BA, 0x3B3E45)
    public static let boardSurface = DLColorToken(0xFBFBF8, 0xECE8E0)
}

/// The six classic sticky-note colours a discussion author picks (doc "Delululand — Discussions"),
/// plus the blank note.
public enum DLNoteColor: String, CaseIterable, Sendable, Identifiable {
    case lemon, peach, pink, lavender, sky, mint, blank

    public var id: String { rawValue }

    /// The note's face.
    public var face: DLColorToken {
        switch self {
        case .lemon: DLColorToken(0xF6EAB0, 0x4F4A2C)
        case .peach: DLColorToken(0xF8D9C3, 0x5B4436)
        case .pink: DLColorToken(0xF5D3DC, 0x563A44)
        case .lavender: DLColorToken(0xE0DAF2, 0x433D5A)
        case .sky: DLColorToken(0xCFE3F3, 0x2F4457)
        case .mint: DLColorToken(0xD4E9DC, 0x34493E)
        case .blank: DLColorToken(0xECE7DE, 0x34312C)
        }
    }

    /// The deeper fold / shadow tone of the same note.
    public var deep: DLColorToken {
        switch self {
        case .lemon: DLColorToken(0xECDC93, 0x45402A)
        case .peach: DLColorToken(0xEFC6A9, 0x4E3A2E)
        case .pink: DLColorToken(0xECBFCB, 0x4A323B)
        case .lavender: DLColorToken(0xD0C8EA, 0x3A354F)
        case .sky: DLColorToken(0xBAD5EC, 0x293B4C)
        case .mint: DLColorToken(0xC0DCCB, 0x2D3F36)
        case .blank: DLColorToken(0xE2DBD0, 0x2D2A26)
        }
    }
}

// MARK: - SwiftUI shorthands (`.foregroundStyle(.dlInk)`, `.background(.dlPaper)`)

public extension ShapeStyle where Self == Color {
    static var dlPaper: Color { DLPalette.paper.color }
    static var dlPaperLetter: Color { DLPalette.paperLetter.color }
    static var dlCell: Color { DLPalette.cell.color }
    static var dlSheet: Color { DLPalette.sheet.color }
    static var dlLine: Color { DLPalette.line.color }
    static var dlPlaceholder: Color { DLPalette.placeholder.color }
    static var dlInk: Color { DLPalette.ink.color }
    static var dlInkQuiet: Color { DLPalette.inkQuiet.color }
    static var dlInkDisabled: Color { DLPalette.inkDisabled.color }
    static var dlSeal: Color { DLPalette.seal.color }
    static var dlSealHue: Color { DLPalette.sealHue.color }
    static var dlSealTint: Color { DLPalette.sealTint.color }
    static var dlSealTintLine: Color { DLPalette.sealTintLine.color }
    static var dlOnSeal: Color { DLPalette.onSeal.color }
    static var dlPostmark: Color { DLPalette.postmark.color }
    static var dlPostmarkHue: Color { DLPalette.postmarkHue.color }
    static var dlUserA: Color { DLPalette.userA.color }
    static var dlUserATint: Color { DLPalette.userATint.color }
    static var dlUserB: Color { DLPalette.userB.color }
    static var dlUserBTint: Color { DLPalette.userBTint.color }
    static var dlError: Color { DLPalette.error.color }
    static var dlErrorTint: Color { DLPalette.errorTint.color }
    static var dlErrorLine: Color { DLPalette.errorLine.color }
    static var dlScrim: Color { DLPalette.scrim.color }
    static var dlShade: Color { DLPalette.shade.color }
    static var dlNewBadge: Color { DLPalette.newBadge.color }
    static var dlOnNewBadge: Color { DLPalette.onNewBadge.color }
    static var dlCountdownChip: Color { DLPalette.countdownChip.color }
    static var dlMarkContainer: Color { DLPalette.markContainer.color }
    /// iOS `secondarySystemFill`: grey capsule buttons and alert buttons (canvas Components).
    static var dlSystemFill: Color { Color(uiColor: .secondarySystemFill) }
    /// iOS `systemRed`: destructive actions in alerts, menus and dialogs.
    static var dlSystemRed: Color { Color(uiColor: .systemRed) }
}
