import SwiftUI
import UIKit

/// Corner radii (web shape tokens; canvas Components). Paper cards keep 4 pt corners.
public enum DLRadius {
    public static let card: CGFloat = 4
    public static let row: CGFloat = 12
    public static let field: CGFloat = 16
    public static let button: CGFloat = 20
    public static let sheet: CGFloat = 24
    public static let groupedCard: CGFloat = 24
}

/// UIKit-drawn chrome that SwiftUI styles through appearance proxies.
@MainActor
public enum DLAppearance {
    /// Navigation bar titles in Manrope (large 800/34, inline 800/17) and the ink colour. The bars
    /// themselves stay system (Liquid Glass on iOS 26+, classic bars before; decision Q2).
    /// Call after `DLFonts.register()`.
    public static func apply() {
        let ink = DLPalette.ink.uiColor
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: DLTextStyle.largeTitle.spec.uiFont(),
            .foregroundColor: ink,
        ]
        bar.titleTextAttributes = [
            .font: DLTextStyle.headline.spec.uiFont(),
            .foregroundColor: ink,
        ]
    }
}
