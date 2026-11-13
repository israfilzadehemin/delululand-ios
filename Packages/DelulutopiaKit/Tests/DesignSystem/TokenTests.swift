import CoreText
@testable import DLDesignSystem
import Testing
import UIKit

@Suite("Tokens")
struct TokenTests {
    private func hex(_ color: UIColor, _ style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    @Test("Colour roles resolve to the web tokens in both themes")
    func colourRolesMatchTheWeb() {
        let expected: [(DLColorToken, UInt32, UInt32)] = [
            (DLPalette.paper, 0xF5F0E8, 0x16181F),
            (DLPalette.paperLetter, 0xE8E1D8, 0x22252E),
            (DLPalette.line, 0xD9D0C5, 0x3B3F4C),
            (DLPalette.ink, 0x33323B, 0xECE6DC),
            (DLPalette.inkQuiet, 0x48536C, 0xA3ADC4),
            (DLPalette.seal, 0x202B45, 0xB4C2EA),
            (DLPalette.sealTint, 0xE4DFF0, 0x2C2A40),
            (DLPalette.onSeal, 0xFFFFFF, 0x141A2C),
            (DLPalette.error, 0xB23A3A, 0xEE8A80),
            (DLPalette.userA, 0xD99A82, 0xD99A82),
            (DLPalette.userB, 0x9CBDB3, 0x9CBDB3),
            (DLPalette.cell, 0xFCFAF6, 0x22252E),
            (DLPalette.sheet, 0xF7F3EC, 0x1C1F27),
        ]
        for (token, light, dark) in expected {
            #expect(hex(token.uiColor, .light) == light)
            #expect(hex(token.uiColor, .dark) == dark)
        }
    }

    @Test("Translucent roles keep their alpha")
    func alphaRoles() {
        #expect(DLPalette.letterRule.light.alpha == 0.16)
        #expect(DLPalette.letterRule.dark.alpha == 0.09)
        #expect(DLPalette.scrim.light.alpha == 0.45)
        #expect(DLPalette.scrim.dark.alpha == 0.6)
    }

    @Test("Every note colour has a face and a deeper fold in both themes")
    func notes() {
        #expect(DLNoteColor.allCases.count == 7)
        #expect(DLNoteColor.lemon.face.light.hex == 0xF6EAB0)
        #expect(DLNoteColor.mint.deep.dark.hex == 0x2D3F36)
    }

    @Test("List stagger: 40 ms a row, capped at 320 ms")
    func stagger() {
        #expect(DLMotion.stagger(0) == 0)
        #expect(abs(DLMotion.stagger(3) - 0.12) < 0.0001)
        #expect(DLMotion.stagger(20) == 0.32)
        #expect(DLMotion.stagger(-1) == 0)
    }
}

@Suite("Fonts")
struct FontTests {
    @Test("Every bundled face registers by its PostScript name")
    func everyFaceRegisters() {
        DLFonts.register()
        for name in DLFontName.allCases {
            #expect(UIFont(name: name.rawValue, size: 17) != nil, "\(name.rawValue)")
        }
        #expect(DLFonts.allAvailable)
    }

    @Test("Manrope carries capital schwa Ə for Azerbaijani")
    func manropeHasSchwa() throws {
        DLFonts.register()
        let font = try #require(UIFont(name: DLFontName.manropeRegular.rawValue, size: 17))
        let ctFont = CTFontCreateWithName(font.fontName as CFString, 17, nil)
        var characters: [UniChar] = [0x018F]
        var glyphs: [CGGlyph] = [0]
        #expect(CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, 1))
    }

    @Test("Every text style resolves its face and keeps a non-negative line spacing")
    func textStyles() {
        DLFonts.register()
        for style in DLTextStyle.allCases {
            let spec = style.spec
            if let face = spec.face {
                #expect(UIFont(name: face.rawValue, size: spec.size) != nil, "\(style)")
            }
            #expect(spec.lineSpacing(atSize: spec.size) >= 0, "\(style)")
            #expect(spec.lineHeight >= spec.size, "\(style)")
        }
    }
}
