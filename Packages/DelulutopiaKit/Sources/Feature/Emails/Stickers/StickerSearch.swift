import DLI18n
import DLNetwork
import Foundation

/// Case- and diacritic-insensitive, as the stamp search: `qucaq` finds "Qucaq".
func stickerFold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en")).lowercased().replacingOccurrences(of: "ı", with: "i")
}

/// SK5: hidden keywords in every language, and the emojis that find a sticker.
func stickerMatches(_ s: Sticker, _ query: String) -> Bool {
    let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty { return true }
    if s.emojis.contains(where: { raw.contains($0) || $0.contains(raw) }) { return true }
    let f = stickerFold(raw)
    return s.keywords.contains { stickerFold($0).contains(f) }
}

struct StickerSection: Identifiable, Equatable {
    let key: String
    let title: String
    let items: [Sticker]
    var add = false
    var id: String { key }
}

/// FS-SK3: Recent · Favourites · Ours (with +) · the packs; empty Recent and Favourites hidden, Ours never.
func stickerSections(_ cat: StickerCatalogue) -> [StickerSection] {
    let by = Dictionary(cat.stickers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var out: [StickerSection] = []
    let recent = cat.recent.compactMap { by[$0] }
    if !recent.isEmpty { out.append(StickerSection(key: "recent", title: t("stickers.recent"), items: recent)) }
    let favs = cat.favourites.compactMap { by[$0] }
    if !favs.isEmpty { out.append(StickerSection(key: "favourites", title: t("stickers.favourites"), items: favs)) }
    out.append(StickerSection(key: "ours", title: t("stickers.ours"), items: cat.stickers.filter { $0.custom != nil }, add: true))
    for p in cat.packs {
        let items = cat.stickers.filter { $0.pack == p.slug }
        if !items.isEmpty { out.append(StickerSection(key: "pack-\(p.slug)", title: p.name, items: items)) }
    }
    return out
}

/// FS-SK18: "Sticker: hug".
func stickerLabel(_ s: Sticker) -> String {
    s.keywords.first.map { t("stickers.labelWith", ["word": $0]) } ?? t("stickers.label")
}
