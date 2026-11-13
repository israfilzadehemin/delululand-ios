import Foundation

/// The languages (doc "Delululand — Languages" L1, L15): English, Azerbaijani, Persian, Turkish, Russian.
/// `rawValue` is what the API stores and accepts.
public enum Lang: String, CaseIterable, Sendable {
    case en, az, fa, tr, ru

    public var tag: String { rawValue }

    /// Persian lays out right to left (L3).
    public var rtl: Bool { self == .fa }

    /// Each language in its own words (L8), so it can be found from any language.
    public var native: String {
        switch self {
        case .en: "English"
        case .az: "Azərbaycanca"
        case .fa: "فارسی"
        case .tr: "Türkçe"
        case .ru: "Русский"
        }
    }

    /// Formatting locale: en-GB (24-hour, day before month), az-AZ, fa-IR, tr-TR, ru-RU.
    public var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_GB")
        case .az: Locale(identifier: "az_AZ")
        case .fa: Locale(identifier: "fa_IR")
        case .tr: Locale(identifier: "tr_TR")
        case .ru: Locale(identifier: "ru_RU")
        }
    }

    public static func parse(_ tag: String?) -> Lang? { tag.flatMap(Lang.init(rawValue:)) }

    /// L6: before sign-in, the phone's first language when it is one of ours, else English.
    public static func device(_ preferred: [String] = Locale.preferredLanguages) -> Lang {
        let code = preferred.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? "" }
        return Lang.parse(code) ?? .en
    }
}
