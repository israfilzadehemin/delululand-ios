import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

/// S13's threads (web emails/useThreads.ts): newest first, 20 per page, page 1 re-read on signals
/// and polled while the stream is down.
@MainActor
@Observable
final class ThreadsModel {
    private(set) var head: [ThreadRow]?
    private var older: [ThreadRow] = []
    private(set) var nextCursor: String?
    @ObservationIgnored private var loadingMore = false
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    var rows: [ThreadRow]? {
        guard let head else { return nil }
        let seen = Set(head.map(\.id))
        return head + older.filter { !seen.contains($0.id) }
    }

    func start() {
        guard refresher == nil else { return }
        let r = Refresher(live: backend.live, signals: ["email", "reaction"], reload: { [weak self] in await self?.loadHead() })
        refresher = r
        r.start()
        Task { await loadHead() }
    }

    func stop() {
        refresher?.stop()
        refresher = nil
    }

    func loadHead() async {
        guard let page = try? await backend.api.threads(limit: 20) else { return }
        head = page.items
        if older.isEmpty { nextCursor = page.nextCursor }
    }

    func loadMore() {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        Task {
            if let page = try? await backend.api.threads(cursor: cursor, limit: 20) {
                older += page.items
                nextCursor = page.nextCursor
            }
            loadingMore = false
        }
    }
}

/// S13 Emails (canvas E-Emails): the credits line, thread cards newest first, compose in the bar.
public struct EmailsScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open
    @State private var model: ThreadsModel?

    public init() {}

    public var body: some View {
        let home = backend.home.home
        Group {
            if let model, let rows = model.rows {
                if rows.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "at").font(.system(size: 44, weight: .light)).foregroundStyle(.dlInkQuiet)
                        Text("No emails yet.").dlText(.headline).foregroundStyle(.dlInk)
                        Text("Start the first one.").dlText(.subheadline).foregroundStyle(.dlInkQuiet)
                        Button("New email") { open(.newEmail) }.buttonStyle(DLButtonStyle(.filled))
                        if let line = creditsLine(home?.emailCredits) { Text(line).font(.caption).foregroundStyle(.dlInkQuiet) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if let line = creditsLine(home?.emailCredits) {
                                Text(line).font(.footnote).foregroundStyle((home?.emailCredits?.left ?? 1) > 0 ? Color.dlInkQuiet : Color.dlError)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                ThreadCard(row: row, home: home)
                                    .dlEnter(.rise, delay: DLMotion.stagger(i))
                                    .onAppear { if i >= rows.count - 3 { model.loadMore() } }
                            }
                            Text(model.nextCursor != nil ? "Loading older threads…" : "That is everything")
                                .dlText(.footnote).foregroundStyle(.dlInkQuiet).frame(minHeight: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle("Emails")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { open(.newEmail) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New email")
            }
        }
        .refreshable { await model?.loadHead() }
        .onAppear {
            if model == nil { model = ThreadsModel(backend: backend) }
            model?.start()
        }
        .onDisappear { model?.stop() }
    }
}

/// FS-E3: subject (bold when unread), "[sender] → [recipient] · HH:MM · N emails", the snippet, "N new".
private struct ThreadCard: View {
    let row: ThreadRow
    let home: Home?
    @Environment(\.dlOpen) private var open

    var body: some View {
        let me = home?.me
        let friend = home?.friend
        let fromMe = row.lastSenderId == me?.id
        let unread = row.unread > 0
        let reacted = row.unseenReactions
        let snippet = reactionWins(row.lastReaction, count: reacted, otherActivityAt: row.lastEmailAt)
            ? noticeLine(row.lastReaction!, count: reacted, reactorName: friend?.nickname ?? "Friend")
            : (row.lastText?.isEmpty == false ? row.lastText! : mediaWords(photos: row.lastMedia?.photos ?? 0, audios: row.lastMedia?.audios ?? 0, videos: row.lastMedia?.videos ?? 0) ?? "")
        Button { open(.thread(row.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.subject)
                        .font(.custom(unread ? DLFontName.literataBold.rawValue : DLFontName.literataSemiBold.rawValue, size: 17, relativeTo: .headline))
                        .foregroundStyle(.dlMailInk)
                        .lineLimit(1)
                    Spacer()
                    if row.unread + reacted > 0 {
                        Text("\(row.unread + reacted) new")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.dlOnMailBlue)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(.dlMailBlue, in: Capsule())
                    }
                }
                Text("\(fromMe ? me?.nickname ?? "You" : friend?.nickname ?? "Friend") → \(fromMe ? friend?.nickname ?? "Friend" : me?.nickname ?? "You") · \(DLTime.clock(row.lastEmailAt)) · \(emailCountWords(row.emailCount))")
                    .font(.system(size: 13))
                    .foregroundStyle(.dlInkQuiet)
                Text(snippet).font(.system(size: 14)).foregroundStyle(.dlMailInk).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(unread ? Color.dlMailUnread : Color.dlMailBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                if unread { UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(.dlMailBlue).frame(width: 4) }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.dlMailLine))
        }
        .buttonStyle(DLPressStyle(scale: 0.99))
    }
}

/// One thread (FS-E5–E10): re-read every 5 s while the stream is down; the newest email unfolded,
/// older folded; "See older" at the bottom; read and seen marks.
@MainActor
@Observable
final class ThreadModel {
    enum UI { case loading, shown, gone, unreachable }

    let id: Int
    private(set) var ui: UI = .loading
    private(set) var thread: ThreadRow?
    private(set) var emails: [Email] = []
    private(set) var olderCursor: String?
    private(set) var loadingOlder = false
    private(set) var olderFailed = false
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored private var seen = false
    @ObservationIgnored let backend: Backend

    init(backend: Backend, id: Int) {
        self.backend = backend
        self.id = id
    }

    func start() {
        guard refresher == nil else { return }
        let r = Refresher(live: backend.live, signals: ["email", "reaction"], poll: Refresher.threadPoll, reload: { [weak self] in await self?.load() })
        refresher = r
        r.start()
        Task { await load() }
    }

    func stop() {
        refresher?.stop()
        refresher = nil
    }

    func load() async {
        do {
            let t = try await backend.api.thread(id: id)
            thread = t.thread
            let ids = Set(t.emails.items.map(\.id))
            let kept = emails.filter { !ids.contains($0.id) && $0.id < (t.emails.items.map(\.id).min() ?? .max) }
            emails = (t.emails.items + kept).sorted { $0.id > $1.id }
            if olderCursor == nil || kept.isEmpty { olderCursor = t.emails.olderCursor }
            ui = .shown
            if t.thread.unread > 0 || t.thread.unseenReactions > 0 || !seen {
                seen = true
                try? await backend.api.threadSeen(id: id)
                backend.home.refreshSoon()
            }
        } catch let e as APIError where e.status == 404 {
            ui = .gone
        } catch {
            if thread == nil { ui = .unreachable }
        }
    }

    func seeOlder() {
        guard let c = olderCursor, !loadingOlder else { return }
        loadingOlder = true
        olderFailed = false
        Task {
            do {
                let page = try await backend.api.olderEmails(threadId: id, cursor: c)
                let ids = Set(emails.map(\.id))
                emails += page.items.filter { !ids.contains($0.id) }.sorted { $0.id > $1.id }
                olderCursor = page.olderCursor
            } catch {
                olderFailed = true
            }
            loadingOlder = false
        }
    }

    func sent(_ e: Email) {
        if !emails.contains(where: { $0.id == e.id }) { emails.insert(e, at: 0) }
    }

    func react(emailId: Int, emoji: String, mine: Bool) async {
        _ = mine ? try? await backend.api.unreact(target: "email", id: emailId, emoji: emoji)
            : try? await backend.api.react(target: "email", id: emailId, emoji: emoji)
        await load()
    }
}

public struct ThreadScreen: View {
    let id: Int
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var model: ThreadModel?
    @State private var composer: EmailComposer?
    @State private var unfolded: Set<Int> = []

    public init(id: Int) {
        self.id = id
    }

    public var body: some View {
        let home = backend.home.home
        let meId = home?.me.id ?? 0
        Group {
            switch model?.ui ?? .loading {
            case .shown:
                if let model {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.thread?.subject ?? "")
                                .font(.custom(DLFontName.literataSemiBold.rawValue, size: 22, relativeTo: .title2))
                                .foregroundStyle(.dlMailInk)
                            if let composer, composer.loaded {
                                ComposerView(composer: composer, credits: home?.emailCredits) { sent in model.sent(sent.email) }
                            }
                            ForEach(Array(model.emails.enumerated()), id: \.element.id) { i, e in
                                EmailCard(email: e, open: i == 0 || unfolded.contains(e.id), meId: meId, home: home,
                                          onToggle: { if unfolded.contains(e.id) { unfolded.remove(e.id) } else { unfolded.insert(e.id) } },
                                          onReact: { emoji, mine in Task { await model.react(emailId: e.id, emoji: emoji, mine: mine) } })
                            }
                            if model.olderCursor != nil {
                                Button(model.loadingOlder ? "Loading older emails…" : "See older") { model.seeOlder() }
                                    .buttonStyle(DLButtonStyle(.text))
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("That is everything").dlText(.footnote).foregroundStyle(.dlInkQuiet).frame(maxWidth: .infinity)
                            }
                            if model.olderFailed { Text("Couldn’t load older emails. Try again.").dlText(.footnote).foregroundStyle(.dlError) }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            case .gone, .unreachable:
                VStack(spacing: 16) {
                    Text(model?.ui == .gone ? "This thread isn’t here." : "Can’t reach \(home?.universe.name ?? "Delulutopia"). Try again.")
                        .dlText(.callout).foregroundStyle(.dlInkQuiet)
                    Button("Back") { dismiss() }.buttonStyle(DLButtonStyle(.outline))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if model == nil {
                model = ThreadModel(backend: backend, id: id)
                model?.start()
                let c = EmailComposer(key: String(id), backend: backend)
                composer = c
                await c.load()
            } else {
                model?.start()
            }
        }
        .onDisappear {
            model?.stop()
            composer?.close()
        }
    }
}

/// One email (FS-E6–E9): sender, time, text, photos, voice, video; folded to one line when older.
private struct EmailCard: View {
    let email: Email
    let open: Bool
    let meId: Int
    let home: Home?
    let onToggle: () -> Void
    let onReact: (String, Bool) -> Void

    @Environment(Backend.self) private var backend
    @State private var lightbox: Int?

    var body: some View {
        let mine = email.senderId == meId
        let sender: Citizen? = mine ? home?.me : home?.friend
        let photos = email.attachments.filter { $0.kind == "photo" }
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    if let sender { CitizenAvatar(sender, size: 32) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sender?.nickname ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(.dlMailInk)
                        if !open {
                            Text(email.text.isEmpty ? (mediaWords(photos: photos.count, audios: email.attachments.filter { $0.kind == "audio" }.count, videos: email.attachments.filter { $0.kind == "video" }.count) ?? "") : email.text)
                                .font(.system(size: 13)).foregroundStyle(.dlInkQuiet).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(DLTime.clock(email.sentAt)).font(.system(size: 12)).foregroundStyle(.dlInkQuiet)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Fold" : "Unfold")
            if open {
                if !email.text.isEmpty {
                    Text(email.text).font(.system(size: 16)).foregroundStyle(.dlMailInk).textSelection(.enabled)
                }
                if !photos.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                            Button { lightbox = i } label: {
                                RemoteImage(p.thumbUrl ?? p.url, contentMode: .fill, maxPixel: 320) { Color.dlMailLine }
                                    .frame(height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .accessibilityLabel("Photo \(i + 1) of \(photos.count), open full size")
                        }
                    }
                }
                ForEach(email.attachments.filter { $0.kind == "audio" }) { a in VoicePlayer(url: a.url, durationMs: a.durationMs) }
                ForEach(email.attachments.filter { $0.kind == "video" }) { v in VideoTile(att: v) }
                ReactionRow(email.reactions, me: meId, compact: true) { emoji in
                    onReact(emoji, email.reactions.first { $0.emoji == emoji }?.userIds.contains(meId) ?? false)
                }
                if mine, let read = email.readAt {
                    Text("Seen \(DLTime.clock(read))").font(.caption).foregroundStyle(.dlInkQuiet)
                }
            }
        }
        .padding(14)
        .background(mine ? Color.dlMailMine : Color.dlMailBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.dlMailLine))
        .fullScreenCover(item: Binding(get: { lightbox.map { LightboxIndex(i: $0) } }, set: { lightbox = $0?.i })) { l in
            Lightbox(items: photos, index: l.i) { lightbox = nil }.environment(backend)
        }
    }

    private struct LightboxIndex: Identifiable {
        let i: Int
        var id: Int { i }
    }
}

/// A video in an email: its poster with a play button; plays full screen.
private struct VideoTile: View {
    let att: Att
    @Environment(Backend.self) private var backend
    @State private var playing = false

    var body: some View {
        Button { playing = true } label: {
            ZStack {
                RemoteImage(att.thumbUrl ?? "", contentMode: .fill, maxPixel: 640) { Color.black }
                Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 4)
                Text(DLTime.mediaLength(ms: att.durationMs)).font(.caption.monospacedDigit()).foregroundStyle(.white)
                    .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Play video")
        .fullScreenCover(isPresented: $playing) {
            VideoPlayerScreen(path: att.url) { playing = false }.environment(backend)
        }
    }
}

/// S14 New email (canvas "new email"): Subject, text, attachments; Send opens the new thread.
public struct NewEmailScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dlOpen) private var open
    @State private var composer: EmailComposer?

    public init() {}

    public var body: some View {
        ScrollView {
            if let composer, composer.loaded {
                ComposerView(composer: composer, credits: backend.home.home?.emailCredits) { sent in
                    dismiss()
                    open(.thread(sent.thread.id))
                }
                .padding(16)
            } else if composer?.failed == true {
                Text("Couldn’t load your draft. Check your connection and try again.").dlText(.callout).foregroundStyle(.dlError).padding(24)
            } else {
                ProgressView().padding(40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle("New email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if composer == nil {
                let c = EmailComposer(key: "new", backend: backend)
                composer = c
                await c.load()
            }
        }
        .onDisappear { composer?.close() }
    }
}
