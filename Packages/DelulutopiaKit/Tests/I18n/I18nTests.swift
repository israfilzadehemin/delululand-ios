@testable import DLI18n
import Foundation
import Testing

/// Doc "Delululand — Languages": the catalogue shared with the web and Android, and the rules for
/// numbers, digits, dates and right-to-left values. Every test names its language, so none touches the
/// language in force.
@Suite("Languages")
struct I18nTests {
    private func placeholders(_ text: String) -> Set<String> {
        var out = Set<String>()
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out.insert(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }

    @Test("Every language says every English sentence, with no placeholder of its own")
    func catalogueParity() {
        #expect(Catalog.en.count > 850)
        for lang in [Lang.az, .fa, .tr, .ru] {
            let catalogue = Catalog.of(lang)
            // Russian adds only the plural forms English has no use for (L17): `_few`, `_many` of a key with `_other`.
            let extra = Set(catalogue.keys).subtracting(Catalog.en.keys)
            #expect(Set(catalogue.keys).isSuperset(of: Catalog.en.keys), "\(lang)")
            #expect(lang == .ru ? !extra.isEmpty : extra.isEmpty, "\(lang): \(extra)")
            for key in extra {
                let other = key.replacingOccurrences(of: #"_(few|many)$"#, with: "_other", options: .regularExpression)
                #expect(Catalog.en[other] != nil, "\(lang) \(key)")
            }
            for (key, en) in Catalog.en {
                let text = catalogue[key] ?? ""
                #expect(!text.isEmpty || en.isEmpty, "\(lang) \(key) is empty")
                #expect(placeholders(text).isSubset(of: placeholders(en)), "\(lang) \(key)")
            }
        }
    }

    @Test("A sentence comes in the language asked for; an unknown key is shown as itself")
    func translates() {
        #expect(translate(.en, "settings.language") == "Language")
        #expect(translate(.az, "settings.language") == "Dil")
        #expect(translate(.fa, "settings.language") == "زبان")
        #expect(translate(.tr, "settings.language") == "Dil")
        #expect(translate(.ru, "settings.language") == "Язык")
        #expect(translate(.ru, "letters.to", ["friend": "Leyla"]) == "Кому: Leyla")
        #expect(translate(.az, "letters.to", ["friend": "Leyla"]) == "Kimə: Leyla")
        #expect(translate(.en, "no.such.key") == "no.such.key")
    }

    @Test("In Persian a Latin value sits in a bidi isolate; Persian values and other languages do not")
    func isolatesLatinInPersian() {
        #expect(fill("به {name}", .fa, ["name": "Leyla"]) == "به \u{2068}Leyla\u{2069}")
        #expect(fill("به {name}", .fa, ["name": "لیلا"]) == "به لیلا")
        #expect(fill("To {name}", .en, ["name": "Leyla"]) == "To Leyla")
        #expect(fill("{name} · {age}", .az, ["name": "Emin", "age": "2 saat"]) == "Emin · 2 saat")
        #expect(fill("{missing} stays", .fa, ["name": "x"]) == "{missing} stays")
    }

    @Test("Numbers and digits follow the language")
    func numbers() {
        #expect(formatNumber(1500, .en) == "1,500")
        #expect(formatNumber(1500, .az) == "1 500")
        #expect(formatNumber(1500, .fa) == "۱٬۵۰۰")
        #expect(formatNumber(1500, .tr) == "1.500")
        #expect(formatNumber(1500, .ru) == "1 500")
        #expect(fill("{n} new", .fa, ["n": 3]) == "۳ new")
        #expect(counter(12, 16, .fa) == "۱۲/۱۶")
        #expect(localDigits("21:05", .fa) == "۲۱:۰۵")
        #expect(localDigits("21:05", .az) == "21:05")
    }

    @Test("Plurals: one and other in English and Azerbaijani; zero counts as one in Persian")
    func plurals() {
        #expect(tn("letters.photos", 1, [:], .en) == "1 photo")
        #expect(tn("letters.photos", 2, [:], .en) == "2 photos")
        #expect(tn("discussions.comments", 3, [:], .az) == "3 şərh")
        #expect(tn("letters.photos", 0, [:], .fa) == translate(.fa, "letters.photos_one", ["n": 0]))
        #expect(tn("emails.count", 4, [:], .tr) == "4 e-posta")
        #expect(tn("discussions.comments", 1, [:], .ru) == "1 комментарий")
        #expect(tn("discussions.comments", 3, [:], .ru) == "3 комментария")
        #expect(tn("discussions.comments", 5, [:], .ru) == "5 комментариев")
        #expect(tn("discussions.comments", 11, [:], .ru) == "11 комментариев")
        #expect(tn("discussions.comments", 21, [:], .ru) == "21 комментарий")
        #expect(tn("emails.creditsLeft", 37, ["time": "04:00"], .ru) == "Сегодня можно отправить ещё 37 имейлов · обновление в 04:00")
        #expect(tn("emails.creditsLeft", 2, ["time": "04:00"], .ru) == "Сегодня можно отправить ещё 2 имейла · обновление в 04:00")
    }

    @Test("Glossary Tone rules: Azerbaijani and Turkish never put a suffix on a placeholder")
    func noSuffixOnAPlaceholder() throws {
        let suffixed = try NSRegularExpression(pattern: #"\{[A-Za-z]+\}['’]?\p{L}"#)
        for lang in [Lang.az, .tr] {
            for (key, value) in Catalog.of(lang) {
                let hit = suffixed.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
                #expect(hit == nil, "\(lang) \(key): \(value)")
            }
        }
    }

    @Test("Glossary Tone rules (ru): a name is never declined nor the subject of a past tense")
    func russianNamesStayNominative() throws {
        let person = #"\{(?:name|friend|nickname|author|authorName|username|who|sender|recipient)\}"#
        let afterPreposition = try NSRegularExpression(
            pattern: #"(?:^|\s)(?:от|у|к|ко|для|с|со|о|об|в|во|на|по|без|из|до|про|при|за|через)\s"# + person,
            options: .caseInsensitive
        )
        let pastTense = try NSRegularExpression(pattern: person + #"\s+[а-яё]+(?:л|ла|ло|ли)(?=[\s.,!?:]|$)"#)
        for (key, value) in Catalog.ru {
            let range = NSRange(value.startIndex..., in: value)
            #expect(afterPreposition.firstMatch(in: value, range: range) == nil, "\(key): \(value)")
            #expect(pastTense.firstMatch(in: value, range: range) == nil, "\(key): \(value)")
        }
    }

    @Test("L6: the phone's language when it is Azerbaijani or Persian, else English")
    func deviceLanguage() {
        #expect(Lang.device(["fa-IR", "en-GB"]) == .fa)
        #expect(Lang.device(["az-Latn-AZ"]) == .az)
        #expect(Lang.device(["de-DE", "az-Latn-AZ"]) == .en)
        #expect(Lang.device(["tr-TR"]) == .tr)
        #expect(Lang.device(["ru-RU", "en-GB"]) == .ru)
        #expect(Lang.allCases.map(\.native) == ["English", "Azərbaycanca", "فارسی", "Türkçe", "Русский"])
        #expect(Lang.parse("fa") == .fa)
        #expect(Lang.parse("xx") == nil)
        #expect(Lang.fa.rtl && !Lang.az.rtl && !Lang.en.rtl)
    }

    private let utc = TimeZone(identifier: "UTC")!

    /// 10 Nov 2026, 21:05 UTC; 19 Aban 1405 in the solar calendar.
    private var tenth: Date { Date(timeIntervalSince1970: 1_794_344_700) }

    @Test("Days: English short months, Azerbaijani months written out, Turkish and Russian from the locale, Persian solar calendar")
    func days() {
        #expect(Dates.day(tenth, year: false, in: utc, .en) == "10 Nov")
        #expect(Dates.day(tenth, year: true, in: utc, .en) == "10 Nov 2026")
        #expect(Dates.day(tenth, year: false, in: utc, .az) == "10 noyabr")
        #expect(Dates.day(tenth, year: true, in: utc, .az) == "10 noyabr 2026")
        #expect(Dates.day(tenth, year: false, in: utc, .fa) == "۱۹ آبان")
        #expect(Dates.day(tenth, year: true, in: utc, .fa) == "۱۹ آبان ۱۴۰۵")
        #expect(Dates.time(tenth, in: utc, .en) == "21:05")
        #expect(Dates.time(tenth, in: utc, .fa) == "۲۱:۰۵")
        #expect(Dates.day(tenth, year: false, in: utc, .tr) == "10 Kasım")
        #expect(Dates.day(tenth, year: true, in: utc, .tr) == "10 Kasım 2026")
        #expect(Dates.day(tenth, year: false, in: utc, .ru) == "10 ноября")
        #expect(Dates.day(tenth, year: true, in: utc, .ru) == "10 ноября 2026")
    }

    @Test("This year is counted in the calendar shown: Nowruz starts a Persian year")
    func sameYearAcrossNowruz() {
        let before = Date(timeIntervalSince1970: 1_773_878_400) // 19 Mar 2026
        let after = Date(timeIntervalSince1970: 1_774_137_600) // 22 Mar 2026
        #expect(Dates.sameYear(before, after, in: utc, .en))
        #expect(!Dates.sameYear(before, after, in: utc, .fa))
    }

    @Test("Every key the app asks for is in the catalogue")
    func everyKeyInTheCodeExists() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let call = try NSRegularExpression(pattern: #"\b(t|tn|tText)\("([a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+)""#)
        var missing: [String] = []
        var seen = 0
        for case let url as URL in files where url.pathExtension == "swift" && !url.path.contains("/I18n/") {
            let text = try String(contentsOf: url, encoding: .utf8)
            for m in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let fn = Range(m.range(at: 1), in: text), let key = Range(m.range(at: 2), in: text) else { continue }
                let name = String(text[key])
                let known = text[fn] == "tn" ? Catalog.en[name + "_other"] != nil : Catalog.en[name] != nil
                seen += 1
                if !known { missing.append("\(url.lastPathComponent): \(name)") }
            }
        }
        #expect(seen > 500)
        #expect(missing.isEmpty, "\(missing)")
    }
}
