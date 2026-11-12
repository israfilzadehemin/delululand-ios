import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

private func byTime(_ a: DComment, _ b: DComment) -> Bool {
    a.createdAt == b.createdAt ? a.id < b.id : a.createdAt < b.createdAt
}

/// Merge a fresh snapshot of comments with what is held (older pages, just-posted ones) without
/// duplicates or resurrecting deleted ones.
func reconcile(_ held: [DComment], _ snap: DComments, posted: [DComment], gone: Set<Int>) -> [DComment] {
    let items = snap.items.filter { !gone.contains($0.id) }
    let oldest = snap.items.min(by: byTime)
    let covers = { (c: DComment) in snap.olderCursor == nil || (oldest.map { !byTime(c, $0) } ?? false) }
    let maxId = snap.items.map(\.id).max() ?? 0
    var out: [Int: DComment] = [:]
    for c in held where !covers(c) && !gone.contains(c.id) { out[c.id] = c }
    for c in items { out[c.id] = c }
    for c in posted where c.id > maxId && !gone.contains(c.id) && out[c.id] == nil { out[c.id] = c }
    return out.values.sorted(by: byTime)
}

/// S11 (FS-D9–D17; web discussions/DiscussionView.tsx, Comments.tsx): the thread re-read every 5 s
/// while the stream is down and on its signals, comments with older pages, seen marks, posting,
/// editing and deleting comments, archive, unarchive, delete and take back.
@MainActor
@Observable
final class DiscussionModel {
    enum UI { case loading, shown(DFull), notArrived(String), gone, unreachable }

    let id: Int
    private(set) var ui: UI = .loading
    private(set) var comments: [DComment] = []
    private(set) var olderCursor: String?
    private(set) var loadingOlder = false
    private(set) var olderFailed = false
    @ObservationIgnored private var olderLoaded = false
    @ObservationIgnored private var posted: [DComment] = []
    @ObservationIgnored private var gone: Set<Int> = []
    @ObservationIgnored private var seenNewest: Int?
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored let backend: Backend

    init(backend: Backend, id: Int) {
        self.backend = backend
        self.id = id
    }

    var cursor: String? { olderLoaded ? olderCursor : (shown?.comments?.olderCursor) }
    var shown: DFull? { if case let .shown(d) = ui { d } else { nil } }

    func start() {
        guard refresher == nil else { return }
        let r = Refresher(live: backend.live, signals: ["discussion", "comment", "reaction"], poll: Refresher.threadPoll,
                          deadlines: { [weak self] in self?.shown.map { [$0.windowEndsAt, $0.arrivesAt] } ?? [] },
                          reload: { [weak self] in await self?.load() })
        refresher = r
        r.start()
        Task {
            await load()
            backend.home.refreshSoon()
        }
    }

    func stop() {
        refresher?.stop()
        refresher = nil
    }

    func load() async {
        do {
            let d = try await backend.api.discussion(id: id)
            ui = .shown(d)
            comments = reconcile(comments, d.comments ?? DComments(items: [], olderCursor: nil), posted: posted, gone: gone)
            markSeen(d)
            if olderLoaded { await reloadRange() }
            refresher?.armDeadline()
        } catch let e as APIError {
            if e.code == "NOT_ARRIVED" {
                let at = e.extra["arrivesAt"]?.string ?? ""
                ui = .notArrived(at)
                let wait = DLTime.remaining(until: at) + 0.3
                if wait < 300 {
                    Task {
                        try? await Task.sleep(for: .seconds(max(0, wait)))
                        await load()
                    }
                }
            } else if e.status == 404 {
                ui = .gone
            } else if shown == nil {
                ui = .unreachable
            }
        } catch {
            if shown == nil { ui = .unreachable }
        }
    }

    /// D6: a newer friend comment shown here moves the seen mark, so the list chip and the tab dot follow.
    private func markSeen(_ d: DFull) {
        let me = backend.home.home?.me.id
        guard let newest = d.comments?.items.last(where: { $0.authorId != me })?.id ?? (d.isNew || d.unseenReactions > 0 ? -1 : nil),
              seenNewest != newest else { return }
        seenNewest = newest
        Task {
            try? await backend.api.discussionSeen(id: id)
            backend.home.refreshSoon()
        }
    }

    private func reloadRange() async {
        guard let snap = try? await backend.api.comments(discussionId: id, from: olderCursor ?? "start") else { return }
        comments = reconcile(comments, snap, posted: posted, gone: gone)
        olderCursor = snap.olderCursor
    }

    func seeOlder() {
        guard let c = cursor, !loadingOlder else { return }
        loadingOlder = true
        olderFailed = false
        Task {
            do {
                let page = try await backend.api.comments(discussionId: id, cursor: c, limit: 20)
                comments = reconcile(comments, DComments(items: page.items + comments, olderCursor: page.olderCursor), posted: [], gone: gone)
                olderCursor = page.olderCursor
                olderLoaded = true
            } catch {
                olderFailed = true
            }
            loadingOlder = false
        }
    }

    /// FS-D14: nil when posted; the error line otherwise (the text stays).
    func post(_ text: String) async -> String? {
        do {
            let c = try await backend.api.comment(discussionId: id, text: text)
            posted.append(c)
            comments = (comments + [c]).sorted(by: byTime)
            return nil
        } catch let e as APIError where (400 ..< 500).contains(e.status) {
            return e.message
        } catch {
            return "Not posted. Try again."
        }
    }

    func edit(_ c: DComment, _ text: String) async -> String? {
        do {
            let updated = try await backend.api.editComment(discussionId: id, commentId: c.id, text: text)
            comments = comments.map { $0.id == c.id ? updated : $0 }
            return nil
        } catch let e as APIError where (400 ..< 500).contains(e.status) {
            if e.status == 404 { drop(c.id) }
            return e.message
        } catch {
            return "Not saved. Try again."
        }
    }

    func delete(_ c: DComment) async -> String? {
        do {
            try await backend.api.deleteComment(discussionId: id, commentId: c.id)
            drop(c.id)
            return nil
        } catch let e as APIError where e.status == 404 {
            drop(c.id)
            return nil
        } catch {
            return "Not deleted. Try again."
        }
    }

    private func drop(_ commentId: Int) {
        gone.insert(commentId)
        comments.removeAll { $0.id == commentId }
    }

    func react(target: String, targetId: Int, emoji: String, mine: Bool) async {
        do {
            _ = mine ? try await backend.api.unreact(target: target, id: targetId, emoji: emoji)
                : try await backend.api.react(target: target, id: targetId, emoji: emoji)
        } catch {}
        await load()
    }

    func archive() async -> String {
        do {
            ui = .shown(try await backend.api.archive(id: id))
            return "Archived for both of you"
        } catch let e as APIError where (400 ..< 500).contains(e.status) {
            return e.message
        } catch {
            return "Not archived. Try again."
        }
    }

    func unarchive() async -> String {
        do {
            ui = .shown(try await backend.api.unarchive(id: id))
            return "Back in Discussions"
        } catch let e as APIError where (400 ..< 500).contains(e.status) {
            return e.message
        } catch {
            return "Not unarchived. Try again."
        }
    }

    /// Delete (or take back while in reach). Nil when done.
    func remove(takeBack: Bool) async -> String? {
        do {
            try await backend.api.deleteDiscussion(id: id)
            backend.home.refreshSoon()
            return nil
        } catch let e as APIError {
            if takeBack, e.code == "WINDOW_CLOSED" { return "Too late: it’s on its way." }
            return takeBack ? "Not taken back. Try again." : "Not deleted. Try again."
        } catch {
            return takeBack ? "Not taken back. Try again." : "Not deleted. Try again."
        }
    }
}

/// S11 Discussion (canvas D-Thread): the opened note with its pin, title, body, photos and voice
/// notes, its reactions; the comments as small askew notes; the composer.
public struct DiscussionScreen: View {
    let id: Int
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var model: DiscussionModel?

    public init(id: Int) {
        self.id = id
    }

    public var body: some View {
        Group {
            switch model?.ui ?? .loading {
            case let .shown(d):
                if let model { ThreadView(d: d, model: model) }
            case let .notArrived(at):
                gone("Arrives at \(DLTime.clock(at))")
            case .gone:
                gone("This discussion isn’t here anymore.")
            case .unreachable:
                gone("Can’t reach \(backend.home.home?.universe.name ?? "Delulutopia"). Try again.")
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle("Discussion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if model == nil { model = DiscussionModel(backend: backend, id: id) }
            model?.start()
        }
        .onDisappear { model?.stop() }
    }

    private func gone(_ text: String) -> some View {
        VStack(spacing: 16) {
            Text(text).dlText(.callout).foregroundStyle(.dlInkQuiet).multilineTextAlignment(.center)
            Button("Back") { dismiss() }.buttonStyle(DLButtonStyle(.outline))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThreadView: View {
    let d: DFull
    let model: DiscussionModel

    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice
    @State private var photo: Int?
    @State private var askTakeBack = false
    @State private var askDelete = false
    @State private var deleting: DComment?
    @State private var editing: DComment?
    @State private var text = ""
    @State private var editText = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let me = backend.home.home?.me
        let friend = backend.home.home?.friend
        let meId = me?.id ?? 0
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = DLTime.now
            let state = LetterState.discussion(now: now, windowEndsAt: d.windowEndsAt, arrivesAt: d.arrivesAt)
            let arrived = state == LetterState.arrived
            let inReach = d.mine && state == LetterState.inReach
            let photos = d.attachments.filter { $0.kind == "photo" }
            let audios = d.attachments.filter { $0.kind == "audio" }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if inReach {
                        ReachBar("\(DLTime.countdown(DLTime.remaining(until: d.windowEndsAt, now: now))) left to take it back") {
                            ReachChip("Edit") { open(.composeDiscussion(editId: d.id)) }
                            ReachChip("Cancel") { askTakeBack = true }
                        }
                    }
                    if let archivedAt = d.archivedAt {
                        let by = d.archivedBy == meId ? "you" : (d.archivedBy != nil ? friend?.nickname ?? "" : "")
                        ReachBar("Archived\(by.isEmpty ? "" : " by \(by)") · \(DLTime.day(archivedAt))") {
                            if d.canUnarchive { ReachChip("Unarchive") { Task { notice(.text(await model.unarchive())) } } }
                        }
                    }
                    Note(.of(d.color), pin: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(d.title).font(.custom(DLFontName.literataSemiBold.rawValue, size: 22, relativeTo: .title2)).foregroundStyle(.dlNoteInk)
                            Text("\(d.mine ? "You" : friend?.nickname ?? "Friend") · Posted \(DLTime.clock(d.postedAt, now: now)) · \(arrived ? "Arrived" : "Arrives") \(DLTime.clock(d.arrivesAt, now: now))\(d.editedAt != nil ? " · Edited" : "")")
                                .font(.custom(DLFontName.manropeMedium.rawValue, size: 12, relativeTo: .caption))
                                .foregroundStyle(.dlNoteInkQuiet)
                            LetterBody(d.doc, size: 16, lineHeight: 25, color: .dlNoteInk)
                            if !photos.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                                            Button { photo = i } label: {
                                                RemoteImage(p.thumbUrl ?? p.url, contentMode: .fill, maxPixel: 320) { Color.black.opacity(0.08) }
                                                    .frame(width: 88, height: 88)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            .accessibilityLabel("Photo \(i + 1) of \(photos.count), open full size")
                                        }
                                    }
                                }
                            }
                            ForEach(audios) { a in VoicePlayer(url: a.url, durationMs: a.durationMs) }
                            if d.mine, !arrived {
                                Text("Arrives for \(friend?.nickname ?? "your friend") in \(DLTime.countdown(DLTime.remaining(until: d.arrivesAt, now: now)))")
                                    .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 13, relativeTo: .footnote).monospacedDigit())
                                    .foregroundStyle(.dlNoteInk)
                            }
                            if arrived {
                                ReactionRow(d.reactions, me: meId, enabled: d.archivedAt == nil) { emoji in
                                    let mine = d.reactions.first { $0.emoji == emoji }?.userIds.contains(meId) ?? false
                                    Task { await model.react(target: "discussion", targetId: d.id, emoji: emoji, mine: mine) }
                                }
                            }
                        }
                        .padding(EdgeInsets(top: 30, leading: 18, bottom: 18, trailing: 18))
                    }
                    .padding(.top, 10)
                    if arrived || d.mine { comments(meId: meId, friend: friend, archived: d.archivedAt != nil, now: now) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if d.canEdit || d.canArchive || d.canUnarchive || d.canDelete {
                    Menu {
                        if d.canEdit { Button("Edit", systemImage: "pencil") { open(.composeDiscussion(editId: d.id)) } }
                        if d.canArchive { Button("Archive", systemImage: "archivebox") { Task { notice(.text(await model.archive())) } } }
                        if d.canUnarchive { Button("Unarchive", systemImage: "tray.and.arrow.up") { Task { notice(.text(await model.unarchive())) } } }
                        if d.canDelete { Button("Delete", systemImage: "trash", role: .destructive) { askDelete = true } }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Discussion options")
                }
            }
        }
        .fullScreenCover(item: Binding(get: { photo.map { PhotoIndex(i: $0) } }, set: { photo = $0?.i })) { p in
            Lightbox(items: d.attachments.filter { $0.kind == "photo" }, index: p.i) { photo = nil }.environment(backend)
        }
        .confirmationDialog("Take it back?", isPresented: $askTakeBack, titleVisibility: .visible) {
            Button("Yes, take it back", role: .destructive) { remove(takeBack: true) }
            Button("No", role: .cancel) {}
        } message: { Text("This deletes the discussion and every comment on it. It can’t be undone.") }
        .confirmationDialog("Delete this discussion?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Yes, delete", role: .destructive) { remove(takeBack: false) }
            Button("No", role: .cancel) {}
        } message: { Text("It disappears for both of you, with every comment and reaction. It can’t be undone.") }
        .confirmationDialog("Delete this comment?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Yes, delete", role: .destructive) {
                guard let c = deleting else { return }
                Task { if let failed = await model.delete(c) { notice(.text(failed)) } }
            }
            Button("No", role: .cancel) {}
        } message: { Text("It disappears for both of you, with its reactions. It can’t be undone.") }
    }

    private struct PhotoIndex: Identifiable {
        let i: Int
        var id: Int { i }
    }

    private func remove(takeBack: Bool) {
        Task {
            if let failed = await model.remove(takeBack: takeBack) {
                notice(.text(failed))
            } else {
                dismiss()
            }
        }
    }

    /// The comments (FS-D12–D15): count, "See older comments", small notes oldest first, the composer.
    @ViewBuilder
    private func comments(meId: Int, friend: Citizen?, archived: Bool, now: Date) -> some View {
        let count = d.commentCount ?? model.comments.count
        VStack(alignment: .leading, spacing: 12) {
            Text(count == 0 ? "No comments yet" : commentWords(count).uppercased())
                .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 11, relativeTo: .caption2)).tracking(0.77)
                .foregroundStyle(.dlInkQuiet)
            if model.cursor != nil {
                Button(model.loadingOlder ? "Loading older comments…" : "See older comments") { model.seeOlder() }
                    .buttonStyle(DLButtonStyle(.outline))
                    .disabled(model.loadingOlder)
            }
            if model.olderFailed {
                Text("Couldn’t load older comments. Try again.").dlText(.footnote).foregroundStyle(.dlError)
            }
            ForEach(Array(model.comments.enumerated()), id: \.element.id) { i, c in
                commentNote(c, index: i, meId: meId, friend: friend, archived: archived, now: now)
            }
            if archived {
                Text("Archived. Unarchive it to comment.").dlText(.footnote).foregroundStyle(.dlInkQuiet)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Write a comment", text: $text, axis: .vertical)
                        .dlText(.input)
                        .lineLimit(1 ... 6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.dlCell, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.dlLine))
                        .disabled(busy)
                    Button(busy ? "Posting…" : "Post") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        busy = true
                        error = nil
                        Task {
                            if let failed = await model.post(t) { error = failed } else { text = "" }
                            busy = false
                        }
                    }
                    .buttonStyle(DLButtonStyle(.filled))
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
            }
        }
    }

    private func commentNote(_ c: DComment, index: Int, meId: Int, friend: Citizen?, archived: Bool, now: Date) -> some View {
        let mine = c.authorId == meId
        return Note(mine ? .of(d.color) : .blank, pin: 0, tilt: index % 2 == 0 ? -0.8 : 0.7) {
            VStack(alignment: .leading, spacing: 8) {
                if editing?.id == c.id {
                    TextField("Edit comment", text: $editText, axis: .vertical).dlText(.input).lineLimit(1 ... 8)
                    HStack {
                        Button("Cancel") { editing = nil }.buttonStyle(DLButtonStyle(.outline)).disabled(busy)
                        Button(busy ? "Saving…" : "Save") {
                            busy = true
                            Task {
                                if let failed = await model.edit(c, editText.trimmingCharacters(in: .whitespacesAndNewlines)) { notice(.text(failed)) } else { editing = nil }
                                busy = false
                            }
                        }
                        .buttonStyle(DLButtonStyle(.filled))
                        .disabled(busy || editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Text(c.text).font(.custom(DLFontName.literataRegular.rawValue, size: 16, relativeTo: .body)).foregroundStyle(.dlNoteInk)
                    Text("\(mine ? "You" : friend?.nickname ?? "Friend") · \(DLTime.clock(c.createdAt, now: now))\(c.editedAt != nil ? " · Edited" : "")")
                        .font(.custom(DLFontName.manropeMedium.rawValue, size: 12, relativeTo: .caption))
                        .foregroundStyle(.dlNoteInkQuiet)
                    ReactionRow(c.reactions, me: meId, compact: true, enabled: !archived) { emoji in
                        let reacted = c.reactions.first { $0.emoji == emoji }?.userIds.contains(meId) ?? false
                        Task { await model.react(target: "comment", targetId: c.id, emoji: emoji, mine: reacted) }
                    }
                }
            }
            .padding(14)
        }
        .padding(mine ? .leading : .trailing, 36)
        .contextMenu {
            if mine, !archived {
                Button("Edit", systemImage: "pencil") {
                    editText = c.text
                    editing = c
                }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = c }
            }
        }
    }
}
