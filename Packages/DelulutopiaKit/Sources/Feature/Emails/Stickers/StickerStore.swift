import DLData
import DLI18n
import DLNetwork
import Foundation
import Observation

/// The sticker catalogue (doc "Delululand — Stickers"; web api/stickers.ts): packs, Ours, Recent and
/// Favourites, reloaded on the `stickers` signal (either citizen added or deleted one of Ours).
@MainActor
@Observable
final class StickerStore {
    static let shared = StickerStore()

    private(set) var catalogue: StickerCatalogue?
    private(set) var failed = false
    @ObservationIgnored private var api: API?
    @ObservationIgnored private var listening: Task<Void, Never>?

    func load(_ backend: Backend) {
        api = backend.api
        if listening == nil {
            let live = backend.live
            listening = Task { [weak self] in
                for await s in live.signals() where s.name == "stickers" || s.name == LiveSignal.ready {
                    await self?.refresh()
                }
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard let api else { return }
        do {
            catalogue = try await api.stickers()
            failed = false
        } catch {
            if catalogue == nil { failed = true }
        }
    }

    func isFavourite(_ id: PublicID) -> Bool { catalogue?.favourites.contains(id) == true }

    /// SK7: the star in the layer and the sheet. The catalogue answers.
    func toggleFavourite(_ id: PublicID) {
        guard let api else { return }
        let on = isFavourite(id)
        Task {
            if on { try? await api.unfavouriteSticker(id: id) } else { try? await api.favouriteSticker(id: id) }
            await refresh()
        }
    }

    /// SK13, FS-SK19–SK22: one image, drawn, cut out or imported. Nil when added, else the words to show.
    func add(_ data: Data, mime: String, keywords: String) async -> String? {
        if let refusal = checkSticker(bytes: data.count, mime: mime) { return refusal }
        guard let api else { return t("common.somethingWentWrong") }
        do {
            _ = try await api.addSticker(data: data, mime: mime, keywords: keywords)
            await refresh()
            return nil
        } catch let e as APIError {
            return e.status == 0 ? t("common.notSavedTryAgain") : e.message
        } catch {
            return t("common.somethingWentWrong")
        }
    }

    /// FS-SK25: either citizen; emails that used it keep it.
    func delete(_ id: PublicID) async -> Bool {
        guard let api else { return false }
        do {
            try await api.deleteSticker(id: id)
            await refresh()
            return true
        } catch {
            return false
        }
    }

    /// Tests only.
    func set(_ c: StickerCatalogue?) { catalogue = c }
}

/// SK15: the server refuses anything larger; said before uploading.
let stickerMaxBytes = 1024 * 1024
let stickerTypes = ["image/png", "image/webp", "image/gif", "image/jpeg"]

/// SK15 said before uploading: over 1 MB, or a type the server can't read.
func checkSticker(bytes: Int, mime: String) -> String? {
    if bytes > stickerMaxBytes { return t("stickers.tooLarge") }
    if !stickerTypes.contains(mime) { return t("stickers.unsupported") }
    return nil
}
