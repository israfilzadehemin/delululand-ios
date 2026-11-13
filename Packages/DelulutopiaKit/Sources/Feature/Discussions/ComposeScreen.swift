import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI

/// S12 compose (FS-D18–D23; web discussions/Compose.tsx): the discussion draft with autosave, or
/// an editing session on a posted discussion (Save). Title, colour, body, photos and voice notes.
@MainActor
@Observable
final class ComposeModel {
    enum Load { case loading, failed, ready }

    let editId: Int?
    private(set) var load: Load = .loading
    private(set) var initial: Doc = .empty
    private(set) var body: Doc = .empty
    private(set) var title = ""
    private(set) var color: DLNoteColor = .lemon
    private(set) var attachments: Attachments?
    private(set) var saver: DraftSaver?
    private(set) var original: DFull?
    @ObservationIgnored let backend: Backend

    init(backend: Backend, editId: Int?) {
        self.backend = backend
        self.editId = editId
    }

    var empty: Bool { body.isEmpty }

    func start() async {
        if backend.server == nil { await backend.loadServerSettings() }
        if let editId {
            guard let d = try? await backend.api.discussion(id: editId) else {
                load = .failed
                return
            }
            original = d
            title = d.title
            color = .of(d.color)
            body = d.doc
            initial = d.doc
            attachments = Attachments(d.attachments, path: "api/discussions/\(editId)/attachments", api: backend.api)
        } else {
            guard let d = try? await backend.api.discussionDraft() else {
                load = .failed
                return
            }
            let saver = DraftSaver { [weak self] version in
                guard let self else { throw CancellationError() }
                return try await self.backend.api.saveDiscussionDraft(title: self.title, body: self.body, version: version, color: self.color.rawValue)
            }
            self.saver = saver
            saver.load(version: d.version, savedAt: d.savedAt)
            apply(d)
        }
        load = .ready
    }

    private func apply(_ d: DDraft) {
        title = d.title
        color = .of(d.color)
        body = d.doc
        initial = d.doc
        if let attachments { attachments.reset(d.attachments) } else {
            attachments = Attachments(d.attachments, path: "api/discussions/draft/attachments", api: backend.api)
        }
    }

    func onBody(_ doc: Doc) {
        body = doc
        saver?.touch()
    }

    func changeTitle(_ text: String) {
        title = text
        saver?.touch()
    }

    func changeColor(_ c: DLNoteColor) {
        color = c
        saver?.touch()
    }

    func loadServer() async -> Doc? {
        guard let d = try? await backend.api.discussionDraft() else { return nil }
        saver?.load(version: d.version, savedAt: d.savedAt)
        apply(d)
        return d.doc
    }

    func deleteDraftAttachment(_ id: String, onFail: @escaping () -> Void) {
        Task { do { try await backend.api.deleteDiscussionDraftAttachment(id: id) } catch { onFail() } }
    }

    func post() async -> String? {
        guard let saver else { return t("common.notPosted") }
        let version: Int
        do { version = try await saver.flush() } catch { return t("common.notPosted") }
        do {
            _ = try await backend.api.post(draftVersion: version)
            backend.home.refreshSoon()
            return nil
        } catch let e as APIError where ["TITLE_REQUIRED", "EMPTY_DISCUSSION", "TITLE_TOO_LONG"].contains(e.code) {
            return e.message
        } catch {
            return t("common.notPosted")
        }
    }

    /// Nil when saved; the error line otherwise.
    func save() async -> String? {
        guard let d = original, let atts = attachments else { return nil }
        do {
            _ = try await backend.api.editDiscussion(id: d.id, title: title.trimmingCharacters(in: .whitespaces), body: body, color: color.rawValue, attachmentIds: atts.done.map(\.id))
            backend.home.refreshSoon()
            return nil
        } catch let e as APIError where (400 ..< 500).contains(e.status) {
            return e.status == 404 ? t("discussions.thisDiscussionIsntHereAnymore") : e.message
        } catch {
            return t("reactions.notSavedTryAgain")
        }
    }

    func discardEdit() async {
        guard let d = original else { return }
        try? await backend.api.discardDiscussionEdit(id: d.id)
    }

    func close() {
        saver?.flushOnLeave()
        saver?.dispose()
        backend.home.refreshSoon()
    }
}

public struct ComposeDiscussionScreen: View {
    let editId: Int?
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dlNotice) private var notice
    @State private var model: ComposeModel?
    @State private var editor = RichEditorState()
    @State private var recorder: VoiceRecorder?
    @State private var postOpen = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDiscard = false

    public init(editId: Int? = nil) {
        self.editId = editId
    }

    public var body: some View {
        Group {
            if let model, case .ready = model.load, let atts = model.attachments {
                form(model, atts)
            } else if let model, case .failed = model.load {
                VStack(spacing: 16) {
                    Text(t("discussions.couldntLoadYourDraftCheck")).dlText(.callout).foregroundStyle(.dlError)
                    Button(t("discussions.back")) { dismiss() }.buttonStyle(DLButtonStyle(.outline))
                }
                .padding(24)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dlPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .task {
            if model == nil {
                let m = ComposeModel(backend: backend, editId: editId)
                model = m
                await m.start()
                if let atts = m.attachments {
                    recorder = VoiceRecorder { data, ms in atts.add(.audio, name: "voice.m4a", mime: "audio/mp4", durationMs: ms) { data } }
                }
            }
        }
        .onDisappear { model?.close() }
    }

    private func form(_ model: ComposeModel, _ atts: Attachments) -> some View {
        let editing = model.original != nil
        let recording = recorder?.recording ?? false
        let canAct = !busy && !model.title.trimmingCharacters(in: .whitespaces).isEmpty && !atts.uploading && !recording
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ForEach(DLNoteColor.pickable) { c in
                            Button { model.changeColor(c) } label: {
                                Circle().fill(c.face.color)
                                    .overlay(Circle().strokeBorder(model.color == c ? Color.dlSeal : Color.black.opacity(0.12), lineWidth: model.color == c ? 2.5 : 1))
                                    .frame(width: 32, height: 32)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.rawValue.capitalized)
                            .accessibilityAddTraits(model.color == c ? .isSelected : [])
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(t("discussions.noteColour"))
                    Note(model.color, pin: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(t("discussions.title"), text: Binding(get: { model.title }, set: { model.changeTitle(String($0.prefix(120))) }), axis: .vertical)
                                .font(.custom(DLFontName.literataSemiBold.name, size: 22, relativeTo: .title2))
                                .foregroundStyle(.dlNoteInk)
                                .lineLimit(1 ... 3)
                            RichEditor(editor, initial: model.initial, placeholder: t("discussions.writeHere")) { model.onBody($0) }
                                .frame(minHeight: 220, alignment: .top)
                        }
                        .padding(EdgeInsets(top: 30, leading: 18, bottom: 18, trailing: 18))
                    }
                    .padding(.top, 10)
                    if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(alignment: .leading, spacing: 4) {
                AttachmentStrip(atts) { item in
                    let index = atts.items.firstIndex(of: item) ?? 0
                    atts.remove(item.key)
                    if !editing, let a = item.att { model.deleteDraftAttachment(a.id) { atts.restore(item, at: index) } }
                }
                .padding(.horizontal, 16)
                if let recorder {
                    AddBar(attachments: atts, recorder: recorder, enabled: true, doodleFull: true) {}
                }
            }
            .padding(.top, 6)
            .background(.dlLetterEnvelope)
        }
        .navigationTitle(editing ? t("discussions.editingADiscussion") : t("discussions.newDiscussion"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editing)
        .toolbar {
            if editing {
                ToolbarItem(placement: .topBarLeading) {
                    Button { confirmDiscard = true } label: { Image(systemName: "chevron.backward") }
                        .accessibilityLabel(t("discussions.backDiscardChanges"))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? (busy ? t("common.saving") : t("discussions.save")) : t("discussions.post")) {
                    if editing {
                        busy = true
                        Task {
                            if let failed = await model.save() { error = failed } else { dismiss() }
                            busy = false
                        }
                    } else {
                        postOpen = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.dlSeal)
                .disabled(!canAct)
            }
        }
        .sheet(isPresented: $postOpen) {
            PostSheet(friend: backend.home.home?.friend?.nickname ?? t("common.friend"),
                      delay: backend.server?.discussionDelay ?? backend.server?.delay ?? "PT60M",
                      window: backend.server?.window ?? "PT5M",
                      onClose: { postOpen = false }) {
                if let failed = await model.post() { return failed }
                postOpen = false
                notice(.text(t("discussions.posted")))
                dismiss()
                return nil
            }
        }
        .alert(t("discussions.aNewerVersionWasSaved"), isPresented: Binding(get: { model.saver?.status == .conflict }, set: { _ in })) {
            Button(t("discussions.keepMine"), role: .cancel) { model.saver?.keepMine() }
            Button(t("discussions.load")) { Task { if let doc = await model.loadServer() { editor.set(doc) } } }
        }
        .confirmationDialog(t("discussions.discardYourChanges"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(t("discussions.yes"), role: .destructive) {
                Task {
                    await model.discardEdit()
                    dismiss()
                }
            }
            Button(t("discussions.no"), role: .cancel) {}
        }
    }
}

/// FS-D21: "Post this discussion?" with the arrival and the end of the take-back window.
private struct PostSheet: View {
    let friend: String
    let delay: String
    let window: String
    let onClose: () -> Void
    let onPost: () async -> String?
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        let now = DLTime.now
        let d = DLTime.isoDuration(delay) ?? 3600
        let w = DLTime.isoDuration(window) ?? 300
        VStack(alignment: .leading, spacing: 14) {
            Text(t("discussions.postThisDiscussion")).dlText(.title2).foregroundStyle(.dlInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("discussions.arrivesForAt", ["friend": friend])).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                Text(DLTime.time(of: now.addingTimeInterval(d))).font(.custom(DLFontName.manropeExtraBold.name, size: 28, relativeTo: .title).monospacedDigit())
            }
            tText("discussions.untilEditOrTakeBack", slot: "time", Text(DLTime.time(of: now.addingTimeInterval(w))).bold())
                .dlText(.callout)
            if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
            HStack(spacing: 8) {
                Button(t("discussions.keepWriting"), action: onClose).buttonStyle(DLButtonStyle(.grey, fullWidth: true)).disabled(posting)
                Button(posting ? t("common.posting") : t("discussions.post")) {
                    posting = true
                    error = nil
                    Task {
                        if let failed = await onPost() {
                            error = failed
                            posting = false
                        }
                    }
                }
                .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                .disabled(posting)
            }
        }
        .foregroundStyle(.dlInk)
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(.dlSheet)
    }
}
