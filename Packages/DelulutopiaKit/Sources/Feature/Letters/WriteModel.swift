import DLData
import DLI18n
import DLNetwork
import DLUI
import Foundation
import Observation

/// S4 Write (FS-W1–W16; web write/DraftWrite.tsx and EditWrite.tsx): the one draft with autosave
/// and conflict handling, or a sent letter still in its window. Attachments upload as they are
/// added; the stamp, the pin and the text ride along on every save.
@MainActor
@Observable
final class WriteModel {
    enum Load { case loading, failed, ready, notEditable(Int) }

    let editId: Int?
    let replyTo: Int?
    private(set) var load: Load = .loading
    private(set) var initial: Doc = .empty
    private(set) var body: Doc = .empty
    private(set) var stamp: StampMark?
    private(set) var pinned: Int?
    private(set) var attachments: Attachments?
    private(set) var empty = true
    private(set) var saver: DraftSaver?
    private(set) var letter: LetterFull?
    var lateByServer = false
    private(set) var stamps: StampCatalogue?
    private(set) var stampsFailed = false
    private(set) var received: [LetterRow] = []
    private(set) var referenced: LetterFull?

    @ObservationIgnored let backend: Backend
    @ObservationIgnored private var receivedCursor: String?
    @ObservationIgnored private var receivedMore = true

    init(backend: Backend, editId: Int?, replyTo: Int?) {
        self.backend = backend
        self.editId = editId
        self.replyTo = replyTo
    }

    private var api: API { backend.api }

    func start() async {
        if backend.server == nil { await backend.loadServerSettings() }
        if let editId { await loadEdit(editId) } else { await loadDraft() }
    }

    private func loadDraft() async {
        guard let d = try? await api.draft() else {
            load = .failed
            return
        }
        let saver = DraftSaver { [weak self] version in
            guard let self else { throw CancellationError() }
            return try await self.api.saveDraft(body: self.body, pinnedLetterId: self.pinned, stampSlug: self.stamp?.slug, version: version)
        }
        self.saver = saver
        saver.load(version: d.version, savedAt: d.savedAt)
        body = d.doc
        initial = d.doc
        stamp = d.stamp
        attachments = Attachments(d.attachments, path: "api/draft/attachments", api: api)
        let freshStart = replyTo == nil && d.doc.isEmpty && d.attachments.isEmpty
        pinned = replyTo ?? (freshStart ? nil : d.pinnedLetterId)
        if pinned != d.pinnedLetterId { saver.touch() }
        empty = d.doc.isEmpty
        load = .ready
        if let pinned { loadReferenced(pinned) }
    }

    private func loadEdit(_ id: Int) async {
        guard let l = try? await api.letter(id: id) else {
            load = .failed
            return
        }
        guard l.canEdit else {
            load = .notEditable(id)
            return
        }
        letter = l
        body = l.doc
        initial = l.doc
        stamp = l.stamp
        let atts = (l.attachments + (l.editAttachments ?? [])).sorted { $0.position < $1.position }
        attachments = Attachments(atts, path: "api/letters/\(id)/attachments", api: api)
        empty = l.doc.isEmpty
        load = .ready
    }

    func onBody(_ doc: Doc) {
        body = doc
        empty = doc.isEmpty
        saver?.touch()
    }

    /// FS-ST3: a stamp is never content.
    func chooseStamp(_ s: StampMark?) {
        stamp = s
        saver?.touch()
    }

    func pin(_ id: Int?) {
        guard id != pinned else { return }
        pinned = id
        saver?.touch()
        if let id { loadReferenced(id) } else { referenced = nil }
    }

    /// Leaving or hiding the screen saves at once (FS-W3).
    func flushOnHide() {
        saver?.flushOnLeave()
    }

    /// Back on this screen: take a newer draft saved elsewhere if nothing here is unsaved (FS-W4).
    func checkNewer() async -> Doc? {
        guard let s = saver, !s.dirty, let d = try? await api.draft(), d.version > s.version, !s.dirty else { return nil }
        apply(d)
        return d.doc
    }

    /// The conflict dialog's Load.
    func loadServer() async -> Doc? {
        guard let d = try? await api.draft() else { return nil }
        apply(d)
        return d.doc
    }

    private func apply(_ d: Draft) {
        body = d.doc
        empty = d.doc.isEmpty
        saver?.load(version: d.version, savedAt: d.savedAt)
        pinned = d.pinnedLetterId
        stamp = d.stamp
        attachments?.reset(d.attachments)
    }

    func keepMine() { saver?.keepMine() }

    func deleteDraftAttachment(_ id: String, onFail: @escaping () -> Void) {
        Task {
            do { try await api.deleteDraftAttachment(id: id) } catch { onFail() }
        }
    }

    enum SendResult { case sent, conflict, failed(String) }

    /// S5 Send: flush, then send exactly that version (FS-S1–S3).
    func send() async -> SendResult {
        guard let saver else { return .failed(t("common.notSent")) }
        let version: Int
        do {
            version = try await saver.flush()
        } catch let e as DraftSaver.FlushError where e.conflict {
            return .conflict
        } catch {
            return .failed(t("common.notSent"))
        }
        do {
            _ = try await api.send(draftVersion: version)
            await backend.home.load()
            backend.letters.refreshSoon()
            return .sent
        } catch let e as APIError {
            return .failed(e.code == "EMPTY_LETTER" ? t("write.nothingToSend") : t("common.notSent"))
        } catch {
            return .failed(t("common.notSent"))
        }
    }

    /// Nil when sent; "" when the window closed (the late dialog takes over); else the error line.
    func sendAgain() async -> String? {
        guard let letter, let attachments else { return nil }
        do {
            _ = try await api.sendAgain(id: letter.id, body: body, attachmentIds: attachments.done.map(\.id), stampSlug: stamp?.slug)
            await backend.home.load()
            backend.letters.refreshSoon()
            return nil
        } catch let e as APIError {
            if e.code == "WINDOW_CLOSED" {
                lateByServer = true
                return ""
            }
            return (400 ..< 500).contains(e.status) ? e.message : t("common.notSent")
        } catch {
            return t("common.notSent")
        }
    }

    func discardEdit() async {
        guard let letter else { return }
        try? await api.discardEdit(id: letter.id)
        backend.home.refreshSoon()
        backend.letters.refreshSoon()
    }

    func keepInDraft() async -> Bool {
        guard let letter else { return false }
        do {
            _ = try await api.keepInDraft(id: letter.id, body: body)
            await backend.home.load()
            backend.letters.refreshSoon()
            return true
        } catch {
            return false
        }
    }

    func loadStamps() {
        guard stamps == nil else { return }
        Task {
            do {
                stamps = try await api.stamps()
                stampsFailed = false
            } catch {
                stampsFailed = true
            }
        }
    }

    func loadReceived() {
        guard receivedMore else { return }
        Task {
            guard let page = try? await api.letters(cursor: receivedCursor, limit: 20, direction: "from") else { return }
            received += page.items.filter { $0.state == LetterState.delivered || $0.state == LetterState.read }
            receivedCursor = page.nextCursor
            receivedMore = page.nextCursor != nil
        }
    }

    /// Showing a letter here fetches it in full, which marks it read (T8), as opening it does.
    func loadReferenced(_ id: Int) {
        guard referenced?.id != id else { return }
        Task { referenced = try? await api.letter(id: id) }
    }

    func close() {
        saver?.flushOnLeave()
        saver?.dispose()
        backend.home.refreshSoon()
    }
}
