import CoreText
import Foundation
import UIKit

/// The bundled faces (decision D12). Manrope carries capital schwa Ə (U+018F) merged from Noto Sans
/// by `tools/fonts/merge_schwa.py`, as the web does with its 'DL Schwa' face; the files are the
/// Android app's. Arabic script falls back to the system faces.
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
