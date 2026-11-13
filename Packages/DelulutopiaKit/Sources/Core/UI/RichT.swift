import DLI18n
import SwiftUI

/// A translated sentence with one placeholder drawn differently, like the web's `rich`:
/// "Until **21:10** you can still take it back." The sentence keeps each language's word order.
public func tText(_ key: String, _ args: [String: Any] = [:], slot: String, _ styled: Text) -> Text {
    let parts = t(key, args).components(separatedBy: "{\(slot)}")
    var text = Text(verbatim: parts[0])
    for part in parts.dropFirst() {
        text = text + styled + Text(verbatim: part)
    }
    return text
}

/// The direction a citizen's own text reads in (web `dir="auto"`): its first strong letter decides; none
/// keeps the screen's direction.
public enum ContentDirection {
    public static func of(_ text: String) -> LayoutDirection? {
        for u in text.unicodeScalars where u.properties.isAlphabetic {
            switch u.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return .rightToLeft
            default: return .leftToRight
            }
        }
        return nil
    }
}

public extension View {
    /// A citizen's own words (letters, titles, comments, emails) laid out in their own direction and
    /// aligned to where they start, whatever the app's language: an English letter in the Persian app
    /// reads from the left, a Persian one in the English app from the right (L3, L10).
    func ownText(_ text: String) -> some View {
        modifier(OwnText(direction: ContentDirection.of(text)))
    }
}

private struct OwnText: ViewModifier {
    @Environment(\.layoutDirection) private var screen
    let direction: LayoutDirection?

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, direction ?? screen)
    }
}
