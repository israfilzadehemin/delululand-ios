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
