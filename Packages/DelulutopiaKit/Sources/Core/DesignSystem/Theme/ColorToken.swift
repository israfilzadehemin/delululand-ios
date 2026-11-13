import SwiftUI
import UIKit

/// An sRGB colour as the web writes it: `#F5F0E8`, or `rgb(72 83 108 / 0.16)` with an alpha.
public struct DLRGBA: Sendable, Hashable {
    public let hex: UInt32
    public let alpha: Double

    public init(_ hex: UInt32, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    public var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A colour role with its light and dark values (web `:root` and `:root[data-theme='dark']`).
/// It resolves against the trait collection, so the in-app theme choice (window style) and the
/// device appearance both apply without any view having to know which is active.
public struct DLColorToken: Sendable, Hashable {
    public let light: DLRGBA
    public let dark: DLRGBA

    public init(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.light = DLRGBA(light, alpha: lightAlpha)
        self.dark = DLRGBA(dark, alpha: darkAlpha)
    }

    /// A role that does not change between themes (signature colours, the lightbox ink).
    public init(same hex: UInt32, alpha: Double = 1) {
        self.light = DLRGBA(hex, alpha: alpha)
        self.dark = DLRGBA(hex, alpha: alpha)
    }

    public func value(for style: UIUserInterfaceStyle) -> DLRGBA {
        style == .dark ? dark : light
    }

    public var uiColor: UIColor {
        let light = self.light
        let dark = self.dark
        return UIColor { traits in
            (traits.userInterfaceStyle == .dark ? dark : light).uiColor
        }
    }

    public var color: Color { Color(uiColor: uiColor) }
}
