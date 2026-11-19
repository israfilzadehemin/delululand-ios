import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI
import UIKit

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
                        Text(t("emails.noEmailsYet")).dlText(.headline).foregroundStyle(.dlInk)
                        Text(t("emails.startTheFirstOne")).dlText(.subheadline).foregroundStyle(.dlInkQuiet)
                        Button(t("emails.newEmail")) { open(.newEmail) }.buttonStyle(DLButtonStyle(.filled))
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
                            Text(model.nextCursor != nil ? t("emails.loadingOlderThreads") : t("emails.thatIsEverything"))
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
        .navigationTitle(t("emails.emails"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { open(.newEmail) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(t("emails.newEmail"))
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
        let unread = row.unread + row.unseenReactions > 0
        let reacted = row.unseenReactions
        // Email Bubbles EB14: the card wears its starter's signature, like their bubbles.
        let who = Who.of(row.startedBy, first: home?.firstCitizen)
        let snippet = reactionWins(row.lastReaction, count: reacted, otherActivityAt: row.lastEmailAt)
            ? noticeLine(row.lastReaction!, count: reacted, reactorName: friend?.nickname ?? t("common.friend"))
            : replyMarked(row, row.lastText?.isEmpty == false ? row.lastText! : mediaWords(photos: row.lastMedia?.photos ?? 0, audios: row.lastMedia?.audios ?? 0, videos: row.lastMedia?.videos ?? 0) ?? "")
        Button { open(.thread(row.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if unread {
                        Circle().fill(Color.dlMailBlue).frame(width: 8, height: 8).accessibilityHidden(true)
                    }
                    Text(row.subject)
                        .font(.custom(unread ? DLFontName.literataBold.name : DLFontName.literataSemiBold.name, size: 17, relativeTo: .headline))
                        .foregroundStyle(.dlMailInk)
                        .lineLimit(1)
                    Spacer()
                    if row.unread + reacted > 0 {
                        Text(t("emails.new", ["fresh": row.unread + reacted]))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.dlOnMailBlue)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(.dlMailBlue, in: Capsule())
                    }
                }
                Text(fill("{from} {arrow} {to} · {time} · {count}", I18n.shared.lang, [
                    "from": fromMe ? me?.nickname ?? t("board.you") : friend?.nickname ?? t("common.friend"),
                    "arrow": I18n.shared.lang.rtl ? "←" : "→",
                    "to": fromMe ? friend?.nickname ?? t("common.friend") : me?.nickname ?? t("board.you"),
                    "time": DLTime.clock(row.lastEmailAt),
                    "count": emailCountWords(row.emailCount),
                ]))
                    .font(.system(size: 13))
                    .foregroundStyle(.dlInkQuiet)
                Text(snippet).font(.system(size: 14)).foregroundStyle(.dlMailInk).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(who.tint, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(unread ? who.signature : who.signature.opacity(0.6), lineWidth: unread ? 2 : 1))
        }
        .buttonStyle(DLPressStyle(scale: 0.99))
    }
}

/// Email Replies RE13: ↩ before a reply's snippet, as Letters B2.
private func replyMarked(_ row: ThreadRow, _ words: String) -> String {
    row.lastIsReply && !words.isEmpty ? "↩ " + words : words
}

/// One thread (FS-E5–E10): re-read every 5 s while the stream is down; the newest email unfolded,
/// shown oldest first as bubbles (doc "Delululand — Email Bubbles"); "See older" at the top; read and seen marks.
@MainActor
@Observable
final class ThreadModel {
    enum UI { case loading, shown, gone, unreachable }

    let id: PublicID
    private(set) var ui: UI = .loading
    private(set) var thread: ThreadRow?
    private(set) var emails: [Email] = []
    private(set) var olderCursor: String?
    private(set) var loadingOlder = false
    private(set) var olderFailed = false
    /// RE12: true while older pages load past the fifth on the way to a quoted email.
    private(set) var jumping = false
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored private var seen = false
    @ObservationIgnored let backend: Backend

    init(backend: Backend, id: PublicID) {
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
            let got = try await backend.api.thread(id: id)
            thread = got.thread
            // Public ids carry no order (doc "Delululand — Public IDs"): older pages are kept by time.
            let fresh = got.emails.items
            let ids = Set(fresh.map(\.id))
            let oldest = fresh.map(\.sentAt).min()
            let kept = emails.filter { e in !ids.contains(e.id) && (oldest.map { e.sentAt < $0 } ?? true) }
            emails = (fresh + kept).sorted { $0.sentAt == $1.sentAt ? $0.id > $1.id : $0.sentAt > $1.sentAt }
            if olderCursor == nil || kept.isEmpty { olderCursor = got.emails.olderCursor }
            ui = .shown
            if got.thread.unread > 0 || got.thread.unseenReactions > 0 || !seen {
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
                emails += page.items.filter { !ids.contains($0.id) }.sorted { $0.sentAt == $1.sentAt ? $0.id > $1.id : $0.sentAt > $1.sentAt }
                olderCursor = page.olderCursor
            } catch {
                olderFailed = true
            }
            loadingOlder = false
        }
    }

    /// RE12: loads older pages until `target` is among the emails; true when it is.
    func ensureLoaded(_ target: PublicID) async -> Bool {
        var pages = 0
        defer { jumping = false }
        while !emails.contains(where: { $0.id == target }) {
            guard let c = olderCursor else { return false }
            pages += 1
            if pages > 5 { jumping = true }
            do {
                let page = try await backend.api.olderEmails(threadId: id, cursor: c)
                let ids = Set(emails.map(\.id))
                emails += page.items.filter { !ids.contains($0.id) }.sorted { $0.sentAt == $1.sentAt ? $0.id > $1.id : $0.sentAt > $1.sentAt }
                olderCursor = page.olderCursor
            } catch {
                olderFailed = true
                return false
            }
        }
        return true
    }

    func sent(_ e: Email) {
        if !emails.contains(where: { $0.id == e.id }) { emails.insert(e, at: 0) }
    }

    func react(emailId: PublicID, emoji: String, mine: Bool) async {
        _ = mine ? try? await backend.api.unreact(target: "email", id: emailId, emoji: emoji)
            : try? await backend.api.react(target: "email", id: emailId, emoji: emoji)
        await load()
    }
}

public struct ThreadScreen: View {
    let id: PublicID
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ThreadModel?
    @State private var composer: EmailComposer?
    @State private var atBottom = true
    @State private var newBelow = false
    @State private var sentId: PublicID?
    @State private var olderAnchor: PublicID?
    /// RE12: the original flashed after a jump.
    @State private var flashId: PublicID?

    public init(id: PublicID) {
        self.id = id
    }

    public var body: some View {
        let home = backend.home.home
        let meId = home?.me.id ?? ""
        Group {
            switch model?.ui ?? .loading {
            case .shown:
                if let model {
                    thread(model, home: home, meId: meId)
                }
            case .gone, .unreachable:
                VStack(spacing: 16) {
                    Text(model?.ui == .gone ? t("emails.threadGone") : t("common.cantReachTryAgain", ["brand": home?.universe.name ?? "Delulutopia"]))
                        .dlText(.callout).foregroundStyle(.dlInkQuiet)
                    Button(t("emails.back")) { dismiss() }.buttonStyle(DLButtonStyle(.outline))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(model?.thread?.subject ?? t("emails.email"))
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

    /// The emails as chat bubbles (doc "Delululand — Email Bubbles"; web ThreadView): oldest at the
    /// top (EB3), opening at the newest, with the reply bar docked at the bottom (EB8).
    private func thread(_ model: ThreadModel, home: Home?, meId: PublicID) -> some View {
        let oldestFirst = Array(model.emails.reversed())
        let first = home?.firstCitizen
        let myNewest = model.emails.first { $0.senderId == meId }?.id
        // RE9, RE11: "You" for my own emails, else the friend's nickname.
        let quoteName: (PublicID) -> String = { id in id == meId ? t("emails.you") : (home?.friend?.id == id ? home?.friend?.nickname ?? "" : "") }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    VStack(spacing: 8) {
                        if model.olderCursor != nil {
                            Button(model.loadingOlder ? t("emails.loadingOlder") : t("emails.seeOlder")) {
                                // Keep the reader's place: the email that was the oldest stays on screen.
                                olderAnchor = oldestFirst.first?.id
                                model.seeOlder()
                            }
                            .buttonStyle(DLButtonStyle(.text))
                        } else if model.emails.count > 20 {
                            Text(t("emails.thatIsEverything")).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        }
                        if model.olderFailed { Text(t("emails.couldntLoadOlderEmailsTry")).dlText(.footnote).foregroundStyle(.dlError) }
                    }
                    .frame(maxWidth: .infinity)
                    ForEach(Array(oldestFirst.enumerated()), id: \.element.id) { i, e in
                        let prev = i > 0 ? oldestFirst[i - 1] : nil
                        let newDay = prev.map { !sameDay($0.sentAt, e.sentAt) } ?? true
                        if newDay { DayChip(label: dayLabel(e.sentAt)) }
                        Bubble(
                            email: e,
                            first: newDay || prev?.senderId != e.senderId,
                            mine: e.senderId == meId,
                            who: Who.of(e.senderId, first: first),
                            home: home,
                            meId: meId,
                            seen: e.id == myNewest ? e.readAt : nil,
                            quoteName: quoteName,
                            quoteWho: { Who.of($0, first: first) },
                            flash: flashId == e.id,
                            onReact: { emoji, mine in Task { await model.react(emailId: e.id, emoji: emoji, mine: mine) } },
                            onReply: { composer?.pickReply(quoteOf(e)) },
                            onOpenQuote: { target in
                                Task {
                                    guard await model.ensureLoaded(target) else { return }
                                    try? await Task.sleep(for: .milliseconds(60))
                                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(target, anchor: .center) }
                                    flashId = target
                                    try? await Task.sleep(for: .seconds(1))
                                    if flashId == target { flashId = nil }
                                }
                            }
                        )
                        .id(e.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92, anchor: e.senderId == meId ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true; newBelow = false }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: model.emails.first?.id)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) {
                // RE12: past five older pages on the way to a quoted email.
                if model.jumping {
                    Label(t("emails.findingOriginal"), systemImage: "arrow.up")
                        .font(.system(size: 13, weight: .heavy))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(Color.dlOnSeal)
                        .background(Color.dlSeal, in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if newBelow {
                    Button {
                        newBelow = false
                        withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Label(t("emails.newEmailBelow"), systemImage: "arrow.down")
                            .font(.system(size: 13, weight: .heavy))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(Color.dlOnSeal)
                            .background(Color.dlSeal, in: Capsule())
                    }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let composer, composer.loaded {
                    DockedComposerView(
                        composer: composer,
                        credits: home?.emailCredits,
                        quoteName: quoteName,
                        quoteWho: { Who.of($0, first: first) }
                    ) { sent in
                        sentId = sent.email.id
                        model.sent(sent.email)
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: model.olderFailed) { _, failed in
                if failed { olderAnchor = nil }
            }
            .onChange(of: model.emails.count) {
                if let a = olderAnchor, !model.loadingOlder {
                    olderAnchor = nil
                    proxy.scrollTo(a, anchor: .top)
                }
            }
            .onChange(of: model.emails.first?.id) { _, newest in
                guard let newest else { return }
                // EB10: at the bottom (or my own send) follow the newest; scrolled up, the pill says so.
                if atBottom || newest == sentId {
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                } else if model.emails.first?.senderId != meId {
                    withAnimation(reduceMotion ? nil : .snappy) { newBelow = true }
                }
            }
        }
    }

    private func sameDay(_ a: String, _ b: String) -> Bool {
        guard let x = DLTime.date(a), let y = DLTime.date(b) else { return false }
        return Calendar.current.isDate(x, inSameDayAs: y)
    }

    /// EB7: "Today", "Yesterday" or the day (FS-T6 forms).
    private func dayLabel(_ iso: String) -> String {
        guard let d = DLTime.date(iso) else { return "" }
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: DLTime.now) { return t("emails.today") }
        if let y = cal.date(byAdding: .day, value: -1, to: DLTime.now), cal.isDate(d, inSameDayAs: y) { return t("emails.yesterday") }
        return DLTime.day(iso)
    }
}

/// EB7: the day between runs.
private struct DayChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.dlInkQuiet)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Color.dlPaperLetter, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One email as a bubble (EB1–EB6): the sender's signature colour (the avatar ring's), on the
/// viewer's side, every one open; the run's first bubble names the sender and points at them.
private struct Bubble: View {
    let email: Email
    let first: Bool
    let mine: Bool
    let who: Who
    let home: Home?
    let meId: PublicID
    let seen: String?
    let quoteName: (PublicID) -> String
    let quoteWho: (PublicID) -> Who
    let flash: Bool
    let onReact: (String, Bool) -> Void
    let onReply: () -> Void
    let onOpenQuote: (PublicID) -> Void

    @Environment(Backend.self) private var backend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lightbox: Int?
    /// RE6: the bubble's sideways offset while a finger drags it, and whether the reply is armed.
    @State private var swipe: CGFloat = 0
    @State private var armed = false
    @State private var dragging: Bool?

    var body: some View {
        let sender: Citizen? = mine ? home?.me : home?.friend
        let photos = email.attachments.filter { $0.kind == "photo" }
        let tail: CGFloat = first ? 4 : 16
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: mine ? 16 : tail,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            topTrailingRadius: mine ? tail : 16
        )
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if first, let sender {
                HStack(spacing: 6) {
                    if mine { name(sender) }
                    CitizenAvatar(sender, size: 24)
                    if !mine { name(sender) }
                }
                .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 8) {
                // RE11: the quote at the top inside the bubble.
                if let q = email.replyTo {
                    BubbleQuote(quote: q, name: quoteName(q.senderId), who: quoteWho(q.senderId)) { onOpenQuote(q.id) }
                }
                if !email.text.isEmpty {
                    Text(linking: email.text).font(.system(size: 16)).foregroundStyle(.dlInk).tint(.dlInk).textSelection(.enabled).ownText(email.text)
                }
                if !photos.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                            Button { lightbox = i } label: {
                                RemoteImage(p.thumbUrl ?? p.url, contentMode: .fill, maxPixel: 320) { Color.dlPaperLetter }
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .accessibilityLabel(t("emails.photoOfOpenFullSize", ["n": i + 1, "count": photos.count]))
                        }
                    }
                }
                ForEach(email.attachments.filter { $0.kind == "audio" }) { a in VoicePlayer(url: a.url, durationMs: a.durationMs) }
                ForEach(email.attachments.filter { $0.kind == "video" }) { v in VideoTile(att: v) }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 9)
            .background(who.tint, in: shape)
            .overlay(shape.stroke(who.signature.opacity(0.75), lineWidth: 1))
            // RE12: a ring around the original after a jump.
            .overlay(shape.stroke(Color.dlMailBlue.opacity(flash ? 0.55 : 0), lineWidth: 3))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: flash)
            // RE6: the bubble follows the finger toward the centre; the ↩ cue shows behind it.
            .background(alignment: mine ? .trailing : .leading) {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.dlInk)
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(width: 32, height: 32)
                    .background(Color.dlPaperLetter, in: Circle())
                    .overlay(Circle().stroke(Color.dlLine, lineWidth: 1))
                    .opacity(min(1, abs(swipe) / swipeArm))
                    .offset(x: -swipe)
                    .accessibilityHidden(true)
            }
            .offset(x: swipe)
            .simultaneousGesture(swipeGesture)
            // EB9: at most 420 pt, and never closer than 56 pt to the other side (about 80 % on a phone).
            .frame(maxWidth: 420, alignment: mine ? .trailing : .leading)
            .padding(mine ? .leading : .trailing, 56)
            HStack(spacing: 6) {
                if mine { replyButton }
                if mine { reactions }
                Text(DLTime.clock(email.sentAt) + (seen.map { " · " + t("emails.seen", ["time": DLTime.clock($0)]) } ?? ""))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.dlInkQuiet)
                if !mine { reactions }
                if !mine { replyButton }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .fullScreenCover(item: Binding(get: { lightbox.map { LightboxIndex(i: $0) } }, set: { lightbox = $0?.i })) { l in
            Lightbox(items: photos, index: l.i) { lightbox = nil }.environment(backend)
        }
    }

    /// RE7: ↩ beside the reactions (a 44 pt target around the 28×24 chip).
    private var replyButton: some View {
        Button(action: onReply) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.dlInkQuiet)
                .flipsForRightToLeftLayoutDirection(true)
                .frame(width: 28, height: 24)
                .overlay(Capsule().stroke(Color.dlLine, lineWidth: 1))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("emails.reply"))
    }

    /// RE6: horizontal only (a mostly vertical start is the scroll's); toward the column's centre —
    /// trailing for the friend's bubble, leading for mine (SwiftUI mirrors both in Persian); arms
    /// at 64 pt with a light tap, springs back on release.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                if dragging == nil { dragging = abs(v.translation.width) > abs(v.translation.height) }
                guard dragging == true else { return }
                let next = swipeOffset(v.translation.width, toward: mine ? -1 : 1)
                let nowArmed = abs(next) >= swipeArm
                if nowArmed, !armed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                armed = nowArmed
                swipe = next
            }
            .onEnded { _ in
                let reply = dragging == true && armed
                dragging = nil
                armed = false
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { swipe = 0 }
                if reply { onReply() }
            }
    }

    private func name(_ c: Citizen) -> some View {
        Text(c.nickname).font(.system(size: 13, weight: .heavy)).foregroundStyle(.dlInk)
    }

    private var reactions: some View {
        ReactionRow(email.reactions, me: meId, compact: true) { emoji in
            onReact(emoji, email.reactions.first { $0.emoji == emoji }?.userIds.contains(meId) ?? false)
        }
        .fixedSize()
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
        .accessibilityLabel(t("media.playVideo"))
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
                Text(t("emails.couldntLoadYourDraftCheck")).dlText(.callout).foregroundStyle(.dlError).padding(24)
            } else {
                ProgressView().padding(40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(t("emails.newEmail"))
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
