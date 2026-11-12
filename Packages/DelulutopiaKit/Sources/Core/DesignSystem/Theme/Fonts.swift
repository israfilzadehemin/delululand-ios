import CoreText
import DLI18n
import Foundation
import UIKit

/// The bundled faces (decision D12). Manrope carries capital schwa Ə (U+018F) merged from Noto Sans
/// by `tools/fonts/merge_schwa.py`, as the web does with its 'DL Schwa' face; the files are the
/// Android app's. Persian (L5) draws in Vazirmatn NL, the Arabic-script cut of Vazirmatn the web and
/// Android use; its Latin falls back to the system face.
public enum DLFontName: String, CaseIterable, Sendable {
    case manropeRegular = "Manrope-Regular"
    case manropeMedium = "Manrope-Medium"
    case manropeSemiBold = "Manrope-SemiBold"
    case manropeBold = "Manrope-Bold"
    case manropeExtraBold = "Manrope-ExtraBold"
    case literataRegular = "Literata-Regular"
    case literataItalic = "Literata-Italic"
    case literataSemiBold = "Literata-SemiBold"
    case literataBold = "Literata-Bold"
    case literataBoldItalic = "Literata-BoldItalic"
    case caveatMedium = "Caveat-Medium"
    case caveatSemiBold = "Caveat-SemiBold"
    case vazirmatnRegular = "Vazirmatn-NL-Regular"
    case vazirmatnMedium = "Vazirmatn-NL-Medium"
    case vazirmatnSemiBold = "Vazirmatn-NL-SemiBold"
    case vazirmatnBold = "Vazirmatn-NL-Bold"
    case vazirmatnExtraBold = "Vazirmatn-NL-ExtraBold"

    /// The face to draw with in the language in force: Persian takes Vazirmatn at the nearest weight
    /// (Literata's serif and Caveat's hand have no Arabic). Read in `body`, so a switch redraws.
    public var name: String { persian(I18n.shared.lang == .fa).rawValue }

    func persian(_ on: Bool) -> DLFontName {
        guard on else { return self }
        return switch self {
        case .manropeRegular, .literataRegular, .literataItalic, .vazirmatnRegular: .vazirmatnRegular
        case .manropeMedium, .caveatMedium, .vazirmatnMedium: .vazirmatnMedium
        case .manropeSemiBold, .literataSemiBold, .caveatSemiBold, .vazirmatnSemiBold: .vazirmatnSemiBold
        case .manropeBold, .literataBold, .literataBoldItalic, .vazirmatnBold: .vazirmatnBold
        case .manropeExtraBold, .vazirmatnExtraBold: .vazirmatnExtraBold
        }
    }
}

public enum DLFonts {
    /// Registers the bundled fonts for this process. Call once at launch (app and extensions) and
    /// before rendering in tests; later calls do nothing.
    public static func register() {
        _ = registered
    }

    /// The fonts are registered from the package bundle rather than listed under `UIAppFonts`, so the
    /// widgets and the share extension can use the same call.
    private static let registered: Bool = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else {
            return false
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// True when every bundled face resolves by its PostScript name.
    public static var allAvailable: Bool {
        register()
        return DLFontName.allCases.allSatisfy { UIFont(name: $0.rawValue, size: 17) != nil }
    }
}
