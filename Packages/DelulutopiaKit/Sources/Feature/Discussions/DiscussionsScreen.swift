import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

func commentWords(_ count: Int?) -> String {
    switch count ?? 0 {
    case 0: ""
    case 1: "1 comment"
    case let n: "\(n) comments"
    }
}

func dState(_ r: DRow, now: Date) -> String { LetterState.discussion(now: now, windowEndsAt: r.windowEndsAt, arrivesAt: r.arrivesAt) }

/// S10's rows (web discussions/useDiscussionRows.ts): newest activity first, 20 per page, page 1
/// re-read on signals and polled while the stream is down, deadlines flip rows locally.
@MainActor
@Observable
final class DiscussionsModel {
    let archived: Bool
    private(set) var head: [DRow]?
    private var older: [DRow] = []
    private(set) var nextCursor: String?
    private(set) var archivedCount = 0
    @ObservationIgnored private var loadingMore = false
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored private let backend: Backend
    static let page = 20

    init(backend: Backend, archived: Bool) {
        self.backend = backend
        self.archived = archived
    }

    var rows: [DRow] {
        guard let fresh = head else { return older }
        let seen = Set(fresh.map(\.id))
        guard fresh.count >= Self.page, let floor = fresh.last.map(sortKey) else { return fresh }
        return fresh + older.filter { !seen.contains($0.id) && below(sortKey($0), floor) }
    }

    func start() {
        guard refresher == nil else { return }
        let r = Refresher(live: backend.live, signals: ["discussion", "comment", "reaction"],
                          deadlines: { [weak self] in (self?.head ?? []).flatMap { [$0.windowEndsAt, $0.arrivesAt] } },
                          reload: { [weak self] in await self?.loadHead() })
        refresher = r
        r.start()
        Task { await loadHead() }
    }

    func stop() {
        refresher?.stop()
        refresher = nil
    }

    func loadHead() async {
        guard let page = try? await backend.api.discussions(limit: Self.page, archived: archived ? true : nil) else { return }
        head = page.items
        archivedCount = page.archivedCount
        if older.isEmpty { nextCursor = page.nextCursor }
        refresher?.armDeadline()
    }

    func loadMore() {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        Task {
            if let page = try? await backend.api.discussions(cursor: cursor, limit: Self.page, archived: archived ? true : nil) {
                older += page.items
                nextCursor = page.nextCursor
            }
            loadingMore = false
        }
    }

    private func sortKey(_ r: DRow) -> (Double, Int) {
        if archived { return (DLTime.date(r.archivedAt)?.timeIntervalSince1970 ?? 0, r.id) }
        let a = DLTime.date(r.arrivesAt)?.timeIntervalSince1970 ?? 0
        let b = DLTime.date(r.activityAt)?.timeIntervalSince1970 ?? 0
        return (max(a, b), r.id)
    }

    private func below(_ a: (Double, Int), _ b: (Double, Int)) -> Bool { a.0 < b.0 || (a.0 == b.0 && a.1 < b.1) }
}

/// S10 Discussions and the Archived list (web discussions/DiscussionsScreen.tsx; canvas
/// D-Discussions, Archived list): big sticky notes, newest activity first, "Archived · N" at the
/// top, compose in the navigation bar.
public struct DiscussionsScreen: View {
    let archived: Bool
    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open
    @State private var model: DiscussionsModel?

    public init(archived: Bool = false) {
        self.archived = archived
    }

    public var body: some View {
        let me = backend.home.home?.me
        let draftEmpty = me?.discussionDraftEmpty ?? true
        let startLabel = draftEmpty ? "Start a discussion" : "Continue your discussion draft"
        Group {
            if let model, let rows = model.head.map({ _ in model.rows }) {
                if rows.isEmpty, model.nextCursor == nil {
                    VStack(spacing: 16) {
                        if !archived, model.archivedCount > 0 { archivedLink(model.archivedCount) }
                        Spacer()
                        Image(systemName: "note.text").font(.system(size: 44, weight: .light)).foregroundStyle(.dlInkQuiet).dlEnter(.rise)
                        if archived {
                            Text("Nothing archived yet.").dlText(.headline).foregroundStyle(.dlInk)
                        } else {
                            Text("No discussions yet.").dlText(.headline).foregroundStyle(.dlInk)
                            Text("Start the first one.").dlText(.subheadline).foregroundStyle(.dlInkQuiet)
                            Button(startLabel) { open(.composeDiscussion(editId: nil)) }.buttonStyle(DLButtonStyle(.filled))
                        }
                        Spacer()
                    }
                    .padding(16)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        list(model: model, rows: rows, now: DLTime.now)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0 ..< 4, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(.dlLetterEnvelope).frame(height: 80) }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(archived ? "Archived" : "Discussions")
        .navigationBarTitleDisplayMode(archived ? .inline : .large)
        .toolbar {
            if !archived {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { open(.composeDiscussion(editId: nil)) } label: {
                        Image(systemName: "note.text.badge.plus")
                            .overlay(alignment: .topTrailing) { if !draftEmpty { DLNewDot().offset(x: 4, y: -2) } }
                    }
                    .accessibilityLabel(startLabel)
                }
            }
        }
        .refreshable { await model?.loadHead() }
        .onAppear {
            if model == nil { model = DiscussionsModel(backend: backend, archived: archived) }
            model?.start()
        }
        .onDisappear { model?.stop() }
    }

    private func archivedLink(_ count: Int) -> some View {
        HStack {
            Spacer()
            Button { open(.archived) } label: {
                Label("Archived · \(count)", systemImage: "archivebox")
                    .font(.custom(DLFontName.manropeBold.rawValue, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(.dlSeal)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Archived discussions: \(count)")
        }
    }

    private func list(model: DiscussionsModel, rows: [DRow], now: Date) -> some View {
        let home = backend.home.home
        let flipped = rows.contains { dState($0, now: now) != $0.state }
        return ScrollView {
            LazyVStack(spacing: 18) {
                if !archived, model.archivedCount > 0 { archivedLink(model.archivedCount) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    NoteRow(r: r, now: now,
                            authorName: r.mine ? (home?.me.nickname ?? "Me") : (home?.friend?.nickname ?? "Friend"),
                            friendName: home?.friend?.nickname ?? "Friend",
                            tilt: i % 2 == 0 ? -0.6 : 0.5)
                        .padding(.top, 8)
                        .dlEnter(.rise, delay: DLMotion.stagger(i))
                        .onAppear { if i >= rows.count - 3 { model.loadMore() } }
                }
                HStack(spacing: 8) {
                    if model.nextCursor != nil {
                        ProgressView().controlSize(.small)
                        Text("Loading older discussions…")
                    } else {
                        Text("That is everything")
                    }
                }
                .dlText(.footnote)
                .foregroundStyle(.dlInkQuiet)
                .frame(minHeight: 40)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onChange(of: flipped) { _, f in if f { Task { await model.loadHead() } } }
    }
}

/// FS-D3–D5: title, "[Author] · Posted HH:MM · N comments", one chip, the unseen ring. Unseen
/// reactions count in "N new" and replace the second line while they are the newest activity.
private struct NoteRow: View {
    let r: DRow
    let now: Date
    let authorName: String
    let friendName: String
    let tilt: Double

    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice

    var body: some View {
        let state = dState(r, now: now)
        let arrived = state == LetterState.arrived
        let hidden = !r.mine && !arrived
        let reacted = r.unseenReactions
        let fresh = r.unseenComments + reacted
        let comments = commentWords(r.commentCount)
        let lastActivity = r.lastCommentAt ?? (r.mine ? r.postedAt : r.arrivesAt)
        let active = r.activityAt.flatMap { a in (DLTime.date(a) ?? .distantPast) > (DLTime.date(r.postedAt) ?? .distantPast) ? a : nil }
        let whenText = active.map { "Active \(DLTime.clock($0, now: now))" } ?? "Posted \(DLTime.clock(r.postedAt, now: now))"
        let meta = reactionWins(r.lastReaction, count: reacted, otherActivityAt: lastActivity)
            ? noticeLine(r.lastReaction!, count: reacted, reactorName: friendName)
            : "\(authorName) · \(whenText)\(r.editedAt != nil ? " · edited" : "")\(comments.isEmpty ? "" : " · \(comments)")"
        if hidden {
            let arrives = DLTime.clock(r.arrivesAt, now: now)
            Button { notice(.text("Arrives at \(arrives)")) } label: {
                Note(.blank, tilt: tilt) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("A discussion is on its way").font(.custom(DLFontName.literataSemiBold.rawValue, size: 17, relativeTo: .body))
                            Text("\(authorName) · arrives \(arrives)").font(.custom(DLFontName.manropeMedium.rawValue, size: 13, relativeTo: .footnote))
                        }
                        .foregroundStyle(.dlNoteInkQuiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        countdown(r.arrivesAt)
                    }
                    .padding(EdgeInsets(top: 26, leading: 16, bottom: 18, trailing: 16))
                }
            }
            .buttonStyle(DLPressStyle(scale: 0.99))
            .accessibilityLabel("A discussion is on its way, arrives \(arrives)")
        } else {
            Button { open(.discussion(r.id)) } label: {
                Note(.of(r.color), unseen: fresh > 0, tilt: tilt) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.title ?? firstLineOf(r.firstLine, media: nil))
                                .font(.custom(DLFontName.literataSemiBold.rawValue, size: 17, relativeTo: .body))
                                .foregroundStyle(.dlNoteInk)
                                .lineLimit(2)
                            Text(meta)
                                .font(.custom(DLFontName.manropeMedium.rawValue, size: 13, relativeTo: .footnote))
                                .foregroundStyle(.dlNoteInkQuiet)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if r.mine, state == LetterState.inReach {
                            Text("\(DLTime.countdown(DLTime.remaining(until: r.windowEndsAt, now: now))) to take back")
                                .font(.custom(DLFontName.manropeBold.rawValue, size: 12, relativeTo: .caption).monospacedDigit())
                                .foregroundStyle(.dlLetterInk)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(.dlCountdownChip, in: Capsule())
                        } else if !arrived {
                            countdown(r.arrivesAt)
                        } else if r.isNew {
                            NewChip()
                        } else if fresh > 0 {
                            NewChip("\(fresh) NEW")
                        }
                    }
                    .padding(EdgeInsets(top: 26, leading: 16, bottom: 18, trailing: 16))
                }
            }
            .buttonStyle(DLPressStyle(scale: 0.99))
        }
    }

    private func countdown(_ iso: String) -> some View {
        Text(DLTime.countdown(DLTime.remaining(until: iso, now: now)))
            .font(.custom(DLFontName.manropeBold.rawValue, size: 16, relativeTo: .headline).monospacedDigit())
            .foregroundStyle(.dlNoteInk)
    }
}
