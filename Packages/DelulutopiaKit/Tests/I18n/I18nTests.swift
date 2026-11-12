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

    @Test("Azerbaijani and Persian say every English sentence, with no placeholder of their own")
    func catalogueParity() {
        #expect(Catalog.en.count > 850)
        for lang in [Lang.az, .fa] {
            let catalogue = Catalog.of(lang)
            #expect(Set(catalogue.keys) == Set(Catalog.en.keys), "\(lang)")
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
    }

    @Test("L6: the phone's language when it is Azerbaijani or Persian, else English")
    func deviceLanguage() {
        #expect(Lang.device(["fa-IR", "en-GB"]) == .fa)
        #expect(Lang.device(["az-Latn-AZ"]) == .az)
        #expect(Lang.device(["de-DE", "az-Latn-AZ"]) == .en)
        #expect(Lang.parse("fa") == .fa)
        #expect(Lang.parse("xx") == nil)
        #expect(Lang.fa.rtl && !Lang.az.rtl && !Lang.en.rtl)
    }

    private let utc = TimeZone(identifier: "UTC")!

    /// 10 Nov 2026, 21:05 UTC; 19 Aban 1405 in the solar calendar.
    private var tenth: Date { Date(timeIntervalSince1970: 1_794_344_700) }

    @Test("Days: English short months, Azerbaijani months written out, Persian solar calendar")
    func days() {
        #expect(Dates.day(tenth, year: false, in: utc, .en) == "10 Nov")
        #expect(Dates.day(tenth, year: true, in: utc, .en) == "10 Nov 2026")
        #expect(Dates.day(tenth, year: false, in: utc, .az) == "10 noyabr")
        #expect(Dates.day(tenth, year: true, in: utc, .az) == "10 noyabr 2026")
        #expect(Dates.day(tenth, year: false, in: utc, .fa) == "۱۹ آبان")
        #expect(Dates.day(tenth, year: true, in: utc, .fa) == "۱۹ آبان ۱۴۰۵")
        #expect(Dates.time(tenth, in: utc, .en) == "21:05")
        #expect(Dates.time(tenth, in: utc, .fa) == "۲۱:۰۵")
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
