import Foundation

/// Day and time text in the language in force (L4, L18): 24-hour everywhere; English `27 Oct`, Azerbaijani
/// `27 oktyabr`, Turkish `27 Ekim`, Russian `27 октября` (the genitive month, no "г."), Persian the solar
/// (Jalali) calendar `۵ آبان` with Persian digits. "This year" is counted in the calendar shown.
public enum Dates {
    /// Written here so every phone says the same as the web and Android.
    static let azMonths = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avqust", "sentyabr", "oktyabr", "noyabr", "dekabr"]

    public static func time(_ date: Date, in zone: TimeZone = .current, _ lang: Lang = I18n.shared.lang) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let p = c.dateComponents([.hour, .minute], from: date)
        return localDigits(String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0), lang)
    }

    /// `10 Nov`, `10 noyabr`, `۱۹ آبان`; with `year` the year follows.
    public static func day(_ date: Date, year: Bool, in zone: TimeZone = .current, _ lang: Lang = I18n.shared.lang) -> String {
        switch lang {
        case .en:
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.timeZone = zone
            f.dateFormat = year ? "d MMM yyyy" : "d MMM"
            return f.string(from: date)
        case .az:
            var c = Calendar(identifier: .gregorian)
            c.timeZone = zone
            let p = c.dateComponents([.day, .month, .year], from: date)
            return "\(p.day ?? 1) \(azMonths[(p.month ?? 1) - 1])" + (year ? " \(p.year ?? 0)" : "")
        case .tr, .ru:
            // "MMMM" after a day is the form a date takes: "Kasım", "ноября".
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = lang.locale
            f.timeZone = zone
            f.dateFormat = year ? "d MMMM yyyy" : "d MMMM"
            return f.string(from: date)
        case .fa:
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .persian)
            f.locale = Locale(identifier: "fa_IR")
            f.timeZone = zone
            f.dateFormat = year ? "d MMMM y" : "d MMMM"
            return localDigits(f.string(from: date), .fa)
        }
    }

    /// Whether `a` and `b` fall in the same year of the calendar shown.
    public static func sameYear(_ a: Date, _ b: Date, in zone: TimeZone = .current, _ lang: Lang = I18n.shared.lang) -> Bool {
        var c = Calendar(identifier: lang == .fa ? .persian : .gregorian)
        c.timeZone = zone
        return c.component(.year, from: a) == c.component(.year, from: b)
    }
}
