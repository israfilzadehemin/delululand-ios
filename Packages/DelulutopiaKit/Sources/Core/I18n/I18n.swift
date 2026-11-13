import Foundation
import Observation

/// The language in force (L6, L8). Observable: a view that reads a text re-renders when it changes, so a
/// pick applies at once. The account's language wins once signed in (Home `me.language`, the live signal
/// `language`); before that the landing pick, then the phone's. The phone's per-app language is not used.
@Observable
public final class I18n: @unchecked Sendable {
    public static let shared = I18n()

    private static let key = "dl-lang"
    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var lang: Lang

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lang = Lang.parse(defaults.string(forKey: Self.key)) ?? Lang.device()
    }

    /// Applies `lang` at once and remembers it on this phone; repositories hear `.dlLanguageChanged`.
    public func set(_ lang: Lang) {
        defaults.set(lang.tag, forKey: Self.key)
        guard lang != self.lang else { return }
        self.lang = lang
        NotificationCenter.default.post(name: .dlLanguageChanged, object: nil)
    }
}

public extension Notification.Name {
    /// Posted after a language switch: reload the server's own words (default moods, stamps).
    static let dlLanguageChanged = Notification.Name("dlLanguageChanged")
}

/// The text for `key` in the language in force, `{name}` placeholders filled from `args`. English when missing.
public func t(_ key: String, _ args: [String: Any] = [:]) -> String {
    translate(I18n.shared.lang, key, args)
}

/// Plural: `<base>_one` or `<base>_other` by `n` (CLDR rules of the three languages); `{n}` is filled too.
public func tn(_ base: String, _ n: Int, _ args: [String: Any] = [:], _ lang: Lang = I18n.shared.lang) -> String {
    let one = lang == .fa ? (n == 0 || n == 1) : n == 1
    let key = one && has(lang, base + "_one") ? base + "_one" : base + "_other"
    return translate(lang, key, args.merging(["n": n]) { a, _ in a })
}

public func translate(_ lang: Lang, _ key: String, _ args: [String: Any] = [:]) -> String {
    fill(template(key, lang), lang, args)
}

/// `key`'s sentence with its placeholders unfilled (English when missing, never the key unless unknown).
public func template(_ key: String, _ lang: Lang = I18n.shared.lang) -> String {
    Catalog.of(lang)[key] ?? Catalog.en[key] ?? key
}

func has(_ lang: Lang, _ key: String) -> Bool { Catalog.of(lang)[key] != nil || Catalog.en[key] != nil }

private let fsi = "\u{2068}"
private let pdi = "\u{2069}"

/// Fills `{name}` once (a value is never re-scanned). Numbers take the language's digits. In a right-to-left
/// language a value with Latin letters sits in a bidi isolate, so "Leyla به Emin · ۱۶:۴۳" keeps its order.
public func fill(_ template: String, _ lang: Lang, _ args: [String: Any]) -> String {
    if args.isEmpty { return template }
    var out = ""
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
        out += rest[..<open]
        guard let close = rest[open...].firstIndex(of: "}") else { break }
        let name = String(rest[rest.index(after: open)..<close])
        if !name.isEmpty, name.allSatisfy({ $0.isASCII && $0.isLetter }), let value = args[name] {
            out += fillValue(value, lang)
        } else {
            out += rest[open...close]
        }
        rest = rest[rest.index(after: close)...]
    }
    return out + rest
}

/// One placeholder's value as `fill` writes it.
public func fillValue(_ value: Any, _ lang: Lang = I18n.shared.lang) -> String {
    switch value {
    case let n as Int: return formatNumber(n, lang)
    case let s as String: return lang.rtl && hasForeignLetter(s) ? fsi + s + pdi : s
    default:
        let s = "\(value)"
        return lang.rtl && hasForeignLetter(s) ? fsi + s + pdi : s
    }
}

/// A letter outside the Arabic script.
func hasForeignLetter(_ s: String) -> Bool {
    s.unicodeScalars.contains { u in
        guard u.properties.isAlphabetic else { return false }
        switch u.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return false
        default: return true
        }
    }
}

/// 1,500 / 1 500 / ۱٬۵۰۰.
public func formatNumber(_ n: Int, _ lang: Lang = I18n.shared.lang) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.numberStyle = .decimal
    let s = f.string(from: NSNumber(value: n)) ?? "\(n)"
    switch lang {
    case .en: return s
    case .az: return s.replacingOccurrences(of: ",", with: " ")
    case .fa: return localDigits(s.replacingOccurrences(of: ",", with: "٬"), .fa)
    }
}

/// "12/16" in the language's digits; digits keep it left to right in a right-to-left line.
public func counter(_ n: Int, _ max: Int, _ lang: Lang = I18n.shared.lang) -> String {
    formatNumber(n, lang) + "/" + formatNumber(max, lang)
}

/// Persian digits ۰–۹ for every 0–9 when the language is Persian (L4); keys and invites never pass here.
public func localDigits(_ s: String, _ lang: Lang = I18n.shared.lang) -> String {
    guard lang == .fa else { return s }
    return String(String.UnicodeScalarView(s.unicodeScalars.map { u in
        (0x30...0x39).contains(u.value) ? Unicode.Scalar(0x06F0 + (u.value - 0x30))! : u
    }))
}
