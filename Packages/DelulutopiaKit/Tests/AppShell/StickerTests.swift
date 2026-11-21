import DLI18n
import DLNetwork
@testable import FeatureEmails
import Foundation
import Testing

/// Stickers (doc "Delululand — Stickers"): search (SK5), the picker's sections (FS-SK3), the quote
/// (FS-SK15), the checks before uploading (SK15); Android StickerSearchTest.
@Suite("Stickers")
@MainActor
struct StickerTests {
    private func s(_ id: String, pack: String? = "love", keywords: [String] = [], emojis: [String] = [], custom: Bool = false) -> Sticker {
        Sticker(
            id: id,
            pack: pack,
            keywords: keywords,
            emojis: emojis,
            url256: "/api/stickers/\(id)/image?size=256",
            url512: "/api/stickers/\(id)/image?size=512",
            custom: custom ? StickerCustom(by: "u1") : nil
        )
    }

    @Test("Keywords match folded in any language, and emojis match")
    func search() {
        let hug = s("1", keywords: ["hug", "Qucaq", "обнять"], emojis: ["🤗"])
        #expect(stickerMatches(hug, "HUG"))
        #expect(stickerMatches(hug, "QÜÇAQ"))
        #expect(stickerMatches(hug, "обн"))
        #expect(stickerMatches(hug, "🤗"))
        #expect(stickerMatches(hug, "  "))
        #expect(!stickerMatches(hug, "sorry"))
    }

    @Test("Empty Recent and Favourites are hidden; Ours always shows with +")
    func sections() {
        let cat = StickerCatalogue(
            packs: [StickerPack(slug: "love", name: "Love", sort: 1), StickerPack(slug: "silly", name: "Silly", sort: 2)],
            stickers: [s("1"), s("2"), s("3", pack: nil, custom: true)]
        )
        let out = stickerSections(cat)
        #expect(out.map(\.key) == ["ours", "pack-love"])
        #expect(out[0].add)
        #expect(out[0].items.map(\.id) == ["3"])
    }

    @Test("Recent and Favourites keep their order and drop stickers no longer there")
    func recentOrder() {
        let cat = StickerCatalogue(
            packs: [StickerPack(slug: "love", name: "Love")],
            stickers: [s("1"), s("2")],
            recent: ["2", "gone", "1"],
            favourites: ["1"]
        )
        let out = stickerSections(cat)
        #expect(out.map(\.key) == ["recent", "favourites", "ours", "pack-love"])
        #expect(out[0].items.map(\.id) == ["2", "1"])
        #expect(out[1].items.map(\.id) == ["1"])
    }

    @Test("A quoted sticker reads Sticker; a sticker email quotes its small image")
    func quote() {
        let e = Email(
            id: "e1",
            threadId: "t1",
            senderId: "u1",
            text: "",
            sentAt: "2026-11-20T10:00:00Z",
            sticker: StickerRef(id: "1", url256: "/s/256", url512: "/s/512")
        )
        let q = quoteOf(e)
        #expect(q.sticker == "/s/256")
        #expect(quoteLine(q) == t("stickers.sticker"))
    }

    @Test("Over 1 MB or an unknown type is refused before uploading")
    func checks() {
        #expect(checkSticker(bytes: 1000, mime: "image/png") == nil)
        #expect(checkSticker(bytes: stickerMaxBytes + 1, mime: "image/png") == t("stickers.tooLarge"))
        #expect(checkSticker(bytes: 1000, mime: "image/heic") == t("stickers.unsupported"))
    }

}
