import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI

/// One letter as S7 has it: loading, shown, or why not.
enum LetterUI {
    case loading
    case shown(LetterFull)
    case notArrived(String)
    case gone
    case unreachable
}

/// The letters opened on a letter page (web letters/LetterView.tsx): fetch (the recipient's first
/// fetch at or after arrival is its read mark, T8), retry a tap just before arrival, re-read a sent
/// letter until it is read.
@MainActor
@Observable
final class LetterReader {
    private(set) var letters: [Int: LetterUI] = [:]
    @ObservationIgnored let backend: Backend
    @ObservationIgnored private var polls: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var signals: Task<Void, Never>?

    init(backend: Backend) {
        self.backend = backend
        let stream = backend.live.signals()
        signals = Task { [weak self] in
            for await signal in stream where signal.name == "letter" {
                guard let self else { return }
                for id in self.letters.keys { await self.reload(id) }
            }
        }
    }

    func stop() {
        signals?.cancel()
        polls.values.forEach { $0.cancel() }
    }

    func open(_ id: Int) {
        if case .shown = letters[id] { return }
        if letters[id] == nil { letters[id] = .loading }
        Task { await reload(id) }
    }

    func reload(_ id: Int) async {
        let ui: LetterUI
        do {
            let letter = try await backend.api.letter(id: id)
            if !letter.isMine {
                // Opening a received letter marks it read: Home's NEW row and the tab dot follow.
                backend.home.refreshSoon()
                backend.letters.refreshSoon()
            }
            ui = .shown(letter)
        } catch let e as APIError {
            if e.code == "NOT_ARRIVED" {
                let at = e.extra["arrivesAt"]?.string ?? ""
                retry(id, at: at)
                ui = .notArrived(at)
            } else if e.status == 404 {
                ui = .gone
            } else if case .shown = letters[id] {
                return
            } else {
                ui = .unreachable
            }
        } catch {
            ui = .unreachable
        }
        letters[id] = ui
        if case let .shown(letter) = ui { pollIfWaiting(letter) }
    }

    /// §3.3: a tap a moment before arrival is retried once at arrivesAt + 300 ms.
    private func retry(_ id: Int, at iso: String) {
        let wait = DLTime.remaining(until: iso) + 0.3
        guard wait < 300 else { return }
        Task {
            try? await Task.sleep(for: .seconds(max(0, wait)))
            await reload(id)
        }
    }

    /// FS-R7: a sent letter not read yet is re-read every 15 s while the stream is down, and at arrival.
    private func pollIfWaiting(_ letter: LetterFull) {
        polls[letter.id]?.cancel()
        guard letter.isMine, letter.state != LetterState.read else { return }
        let untilArrival = DLTime.remaining(until: letter.arrivesAt) + 0.5
        let live = backend.live.isLive
        let wait: Double
        if untilArrival > 0.5, live || untilArrival < 15 {
            wait = untilArrival
        } else if live {
            return
        } else {
            wait = 15
        }
        polls[letter.id] = Task {
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await reload(letter.id)
        }
    }

    func cancel(_ id: Int) async -> LetterActions.CancelResult {
        let result = await LetterActions.cancel(id, backend: backend)
        if result == .done {
            letters[id] = nil
            backend.letters.refreshSoon()
        } else {
            await reload(id)
        }
        return result
    }
}

private func openable(_ r: LetterRow, now: Date) -> Bool {
    if r.isMine { return true }
    let s = LetterState.of(r, now: now)
    return s == LetterState.delivered || s == LetterState.read
}

/// S7 (FS-R4–R10; web letters/LetterView.tsx, LetterSwipe.tsx; canvas C-Letter-*). Received: the
/// header with the frozen mood, the body, photos, voice notes, the doodle, and the bottom bar
/// ‹ Reply ›. Sent: the in-reach bar while the window is open and the status line Sent → Delivered →
/// Read. Swipe sideways for the next older or newer letter (I-6); letters still on their way to me
/// are skipped.
public struct LetterScreen: View {
    let id: Int

    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open
    @Environment(\.dismiss) private var dismiss
    @State private var reader: LetterReader?
    @State private var current: Int

    public init(id: Int) {
        self.id = id
        _current = State(initialValue: id)
    }

    private var ids: [Int] {
        let now = DLTime.now
        let list = backend.letters.rows.filter { $0.id == id || openable($0, now: now) }.map(\.id)
        return list.contains(id) ? list : [id]
    }

    public var body: some View {
        let ids = ids
        let friend = backend.home.home?.friend?.nickname ?? t("common.friend")
        let shown: LetterFull? = if case let .shown(l) = reader?.letters[current] { l } else { nil }
        Group {
            if let reader {
                TabView(selection: $current) {
                    ForEach(ids, id: \.self) { letterId in
                        page(letterId, reader: reader).tag(letterId)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                Color.dlPaper
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(shown.map { "\($0.isMine ? "To" : "From") \(friend)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let shown, !shown.isMine {
                ToolbarItemGroup(placement: .bottomBar) {
                    let i = ids.firstIndex(of: current) ?? 0
                    Button { withAnimation { current = ids[i + 1] } } label: { Image(systemName: "chevron.backward") }
                        .disabled(i >= ids.count - 1)
                        .accessibilityLabel(t("letters.olderLetter"))
                    Spacer()
                    Button { open(.write(replyTo: shown.id)) } label: {
                        Label(t("letters.reply"), systemImage: "arrowshape.turn.up.backward")
                            .labelStyle(.titleAndIcon)
                            .font(.custom(DLFontName.manropeExtraBold.name, size: 16, relativeTo: .headline))
                            .padding(.horizontal, 22)
                            .frame(height: 44)
                            .foregroundStyle(.dlOnSeal)
                            .background(.dlSeal, in: Capsule())
                    }
                    .buttonStyle(DLPressStyle())
                    Spacer()
                    Button { withAnimation { current = ids[i - 1] } } label: { Image(systemName: "chevron.forward") }
                        .disabled(i <= 0)
                        .accessibilityLabel(t("letters.newerLetter"))
                }
            }
        }
        .onAppear {
            if reader == nil { reader = LetterReader(backend: backend) }
            backend.letters.attach()
            reader?.open(current)
        }
        .onDisappear {
            backend.letters.detach()
        }
        .onChange(of: current) { _, now in
            reader?.open(now)
            if ids.last == now, backend.letters.hasMore { backend.letters.loadMore() }
        }
    }

    @ViewBuilder
    private func page(_ letterId: Int, reader: LetterReader) -> some View {
        switch reader.letters[letterId] {
        case let .shown(letter):
            LetterContent(letter: letter, swiped: letterId != id, reader: reader)
        case let .notArrived(at):
            Gone(text: t("letters.arrivesAt", ["time": DLTime.clock(at)])) { dismiss() }
        case .gone:
            Gone(text: t("letters.thisLetterIsntHereAnymore")) { dismiss() }
        case .unreachable:
            Gone(text: t("letters.cantReachTryAgain", ["brand": backend.home.home?.universe.name ?? "Delulutopia"])) { dismiss() }
        default:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Gone: View {
    let text: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(text).dlText(.callout).foregroundStyle(.dlInkQuiet).multilineTextAlignment(.center)
            Button(t("letters.back"), action: onBack).buttonStyle(DLButtonStyle(.outline))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LetterContent: View {
    let letter: LetterFull
    let swiped: Bool
    let reader: LetterReader

    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice
    @Environment(\.dlMotionEnabled) private var motion
    @State private var photo: Int?
    @State private var doodleOpen = false
    @State private var askCancel = false
    @State private var reveal: Bool
    @State private var opening: Bool

    init(letter: LetterFull, swiped: Bool, reader: LetterReader) {
        self.letter = letter
        self.swiped = swiped
        self.reader = reader
        // A received letter opened for the first time writes itself onto the paper (a tap shows it
        // all), after its envelope opens, unless a swipe brought it here.
        let fresh = !letter.isMine && (letter.readAt == nil || -DLTime.remaining(until: letter.readAt) < 30)
        _reveal = State(initialValue: fresh)
        _opening = State(initialValue: fresh && !swiped)
    }

    private var fresh: Bool { !letter.isMine && (letter.readAt == nil || -DLTime.remaining(until: letter.readAt) < 30) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = DLTime.now
            sheet(now: now)
        }
        .fullScreenCover(item: Binding(get: { photo.map { PhotoIndex(i: $0) } }, set: { photo = $0?.i })) { p in
            Lightbox(items: letter.attachments.filter { $0.kind == "photo" }, index: p.i) { photo = nil }
                .environment(backend)
        }
        .fullScreenCover(isPresented: $doodleOpen) {
            if let doodle = letter.attachments.first(where: { $0.kind == "doodle" }) {
                Lightbox(items: [doodle], index: 0, title: t("letters.doodle")) { doodleOpen = false }
                    .environment(backend)
            }
        }
        .takeBackDialog(
            isPresented: $askCancel,
            friend: backend.home.home?.friend?.nickname ?? t("common.friend"),
            draftEmpty: backend.home.home?.me.draftEmpty != false
        ) {
            Task {
                switch await reader.cancel(letter.id) {
                case .done: open(.write())
                case .tooLate: notice(.text(LetterActions.tooLate))
                case .failed: notice(.text(LetterActions.notCancelled))
                }
            }
        }
        .task(id: opening) {
            guard opening else { return }
            if !motion {
                opening = false
                return
            }
            try? await Task.sleep(for: .milliseconds(1100))
            opening = false
        }
    }

    private struct PhotoIndex: Identifiable {
        let i: Int
        var id: Int { i }
    }

    private func sheet(now: Date) -> some View {
        let home = backend.home.home
        let sent = letter.isMine
        let sender: Citizen? = sent ? home?.me : home?.friend
        let state = LetterState.of(now: now, windowEndsAt: letter.windowEndsAt, arrivesAt: letter.arrivesAt, readAt: letter.readAt)
        let inReach = sent && state == LetterState.inReach
        let arrived = state == LetterState.delivered || state == LetterState.read
        let feeling: String? = if let e = letter.moodEmoji, !e.isEmpty, let l = letter.moodLabel, !l.isEmpty { "\(e) \(l)" } else { Moods.text(letter.moodAtSend) }
        let photos = letter.attachments.filter { $0.kind == "photo" }
        let audios = letter.attachments.filter { $0.kind == "audio" }
        let doodle = letter.attachments.first { $0.kind == "doodle" }
        let mediaDelay = fresh && !swiped ? 1.0 : 0.26
        let first = home?.firstCitizen
        return GeometryReader { geo in ScrollView {
            VStack(spacing: 10) {
                if inReach {
                    ReachBar(t("letters.leftToEditOrCancel", ["countdown": DLTime.countdown(DLTime.remaining(until: letter.windowEndsAt, now: now))])) {
                        ReachChip(t("letters.edit")) { open(.write(editId: letter.id)) }
                        ReachChip(t("letters.cancel")) { askCancel = true }
                    }
                }
                ZStack(alignment: .top) {
                    Paper {
                        VStack(alignment: .leading, spacing: 0) {
                            // Head: who, feeling, times; a double rule under it.
                            HStack(spacing: 12) {
                                if let sender { CitizenAvatar(sender, size: 40) }
                                VStack(alignment: .leading, spacing: 2) {
                                    (Text(sender?.nickname ?? "").font(.custom(DLFontName.manropeBold.name, size: 15, relativeTo: .subheadline))
                                        + Text(feeling.map { " " + t("letters.feeling", ["feeling": $0]) } ?? "")
                                        .font(.custom(DLFontName.manropeMedium.name, size: 15, relativeTo: .subheadline))
                                        .foregroundColor(.dlInkQuiet))
                                        .foregroundStyle(.dlLetterInk)
                                    Text(arrived ? t("letters.timesArrived", ["sent": DLTime.clock(letter.sentAt, now: now), "arrived": DLTime.clock(letter.arrivesAt, now: now)])
                                        : t("letters.timesArrives", ["sent": DLTime.clock(letter.sentAt, now: now), "arrives": DLTime.clock(letter.arrivesAt, now: now)]))
                                        .font(.custom(DLFontName.manropeMedium.name, size: 12, relativeTo: .caption).monospacedDigit())
                                        .foregroundStyle(.dlInkQuiet)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(EdgeInsets(top: 16, leading: 16, bottom: 15, trailing: letter.stamp != nil ? 84 : 16))
                            .overlay(alignment: .bottom) {
                                VStack(spacing: 2) {
                                    Rectangle().fill(.dlLetterRule).frame(height: 1)
                                    Rectangle().fill(.dlLetterRule).frame(height: 1)
                                }
                            }
                            if let reply = letter.replyTo {
                                ReplyQuote(reply: reply, friendName: home?.friend?.nickname ?? t("common.friend"), now: now) {
                                    open(.letter(reply.id))
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                            }
                            LetterBody(letter.doc, reveal: reveal && !opening)
                                .frame(minHeight: 196, alignment: .top)
                                .background(alignment: .top) { RuledLines(step: 28) }
                                .padding(EdgeInsets(top: letter.replyTo != nil ? 12 : 18, leading: 20, bottom: 18, trailing: 20))
                                .contentShape(Rectangle())
                                .onTapGesture { if reveal { reveal = false } }
                            Spacer(minLength: 0)
                            if doodle != nil || !photos.isEmpty || !audios.isEmpty || sent {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let doodle {
                                        Button { doodleOpen = true } label: {
                                            RemoteImage(doodle.url, contentMode: .fit, maxPixel: 1024) { Color.dlLetterSheet }
                                                .aspectRatio(1, contentMode: .fit)
                                                .overlay(Rectangle().strokeBorder(.dlLine))
                                                .rotationEffect(.degrees(0.3))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(t("letters.doodleOpenFullSize"))
                                    }
                                    if !photos.isEmpty {
                                        HStack(spacing: 12) {
                                            ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                                                Print(url: p.thumbUrl ?? p.url, tilt: i % 2 == 0 ? -1.5 : 1.2) { photo = i }
                                                    .accessibilityLabel(t("letters.photoOfOpenFullSize", ["n": i + 1, "count": photos.count]))
                                                    .dlEnter(.popIn, delay: mediaDelay)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    ForEach(Array(audios.enumerated()), id: \.element.id) { i, a in
                                        VoicePlayer(url: a.url, durationMs: a.durationMs, label: audios.count > 1 ? t("letters.voiceNoteN", ["n": i + 1]) : t("letters.voiceNoteLower"))
                                            .dlEnter(.popIn, delay: mediaDelay)
                                    }
                                    if sent { StatusLine(letter: letter, state: state, now: now) }
                                }
                                .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                                .background(Color.dlLetterSheet)
                                .overlay(alignment: .top) {
                                    Line().stroke(Color.dlLine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])).frame(height: 1.5)
                                }
                            }
                            Spacer().frame(height: 20)
                        }
                    }
                    .frame(minHeight: max(0, geo.size.height - (inReach ? 76 : 0) - (sent ? 24 : 12)))
                    .dlEnter(.paper, delay: fresh && !swiped ? 0.62 : 0.04)
                    .overlay(on: .topRight) {
                        if let stamp = letter.stamp {
                            StampImage(url: stamp.imageUrl, name: stamp.name, width: 64)
                                .rotationEffect(.degrees(2))
                                .shadow(color: .dlShade.opacity(0.25), radius: 1, y: 1)
                                .padding(.top, 10)
                                .padding(.trailing, 10)
                                .dlEnter(.stamp, delay: fresh && !swiped ? 1.04 : 0.38)
                        }
                    }
                    if opening {
                        EnvelopeOpening(seal: Who.of(sender?.id, first: first).signature) { opening = false }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, sent ? 24 : 12)
            .frame(minHeight: geo.size.height, alignment: .top)
        } }
        .environment(\.dlFirstCitizen, first)
    }
}

/// The letter sheet: margin line, a folded corner, a soft shadow.
private struct Paper<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(alignment: .leading) {
                Rectangle().fill(.dlLetterMargin).frame(width: 1).padding(.leading, 11)
            }
            .background(.dlLetterSheet)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(on: .bottomRight) { DogEar().scaleEffect(26 / 14, anchor: .bottomTrailing) }
            .shadow(color: .dlShade.opacity(0.14), radius: 3, y: 1)
    }
}

/// Ruled paper under the body: one rule per 28 pt line, running on down the sheet.
private struct RuledLines: View {
    let step: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let s = step * scale
            var y = s - 1
            while y < size.height + 4000 {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.dlLetterRule))
                y += s
            }
        }
        .frame(height: 4000, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// A photo print taped onto the sheet: a 3 pt white border, a tilt, a strip of tape.
private struct Print: View {
    let url: String
    let tilt: Double
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            RemoteImage(url, contentMode: .fill, maxPixel: 256) { Color.dlLetterEnvelope }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .padding(3)
                .background(.dlLetterPrint, in: RoundedRectangle(cornerRadius: 2))
                .shadow(color: .dlShade.opacity(0.2), radius: 2, y: 1)
                .overlay(alignment: .top) {
                    Rectangle().fill(.dlLetterTape).frame(width: 22, height: 9).rotationEffect(.degrees(-4)).offset(y: -5)
                }
                .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(DLPressStyle())
    }
}

/// Replies B1: the letter this one answers, clipped above the text. Opens that letter.
private struct ReplyQuote: View {
    let reply: ReplyRef
    let friendName: String
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        let mine = reply.direction == "to"
        let at = DLTime.clock(reply.sentAt, now: now)
        let line = firstLineOf(reply.firstLine, media: reply.media)
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                Label(mine ? t("letters.inReplyToMine", ["time": at]) : t("letters.inReplyToFriends", ["friend": friendName, "time": at]), systemImage: "arrowshape.turn.up.backward")
                    .font(.custom(DLFontName.manropeMedium.name, size: 12, relativeTo: .caption))
                    .foregroundStyle(.dlInkQuiet)
                    .padding(.leading, 12)
                if !line.isEmpty {
                    Text(line)
                        .font(.custom(DLFontName.literataRegular.name, size: 14, relativeTo: .body))
                        .foregroundStyle(.dlLetterInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 12, leading: 15, bottom: 8, trailing: 12))
            .background(alignment: .leading) { Rectangle().fill(.dlUserA).frame(width: 3) }
            .background(.dlLetterSlip, in: UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
            .shadow(color: .dlShade.opacity(0.15), radius: 1.5, y: 1)
            .rotationEffect(.degrees(-0.4))
            .overlay(alignment: .topLeading) {
                PaperClip().stroke(Color.dlInkQuiet, lineWidth: 1.6).frame(width: 14, height: 30).offset(x: 10, y: -12)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityLabel(mine ? t("letters.inReplyToMineOpen", ["time": at]) : t("letters.inReplyToFriendsOpen", ["friend": friendName, "time": at]))
    }

    private struct PaperClip: Shape {
        func path(in rect: CGRect) -> Path {
            let sx = rect.width / 14, sy = rect.height / 30
            var p = Path()
            p.move(to: CGPoint(x: 4 * sx, y: 28 * sy))
            p.addLine(to: CGPoint(x: 4 * sx, y: 6 * sy))
            p.addCurve(to: CGPoint(x: 10 * sx, y: 6 * sy), control1: CGPoint(x: 4 * sx, y: 2 * sy), control2: CGPoint(x: 10 * sx, y: 2 * sy))
            p.addLine(to: CGPoint(x: 10 * sx, y: 24 * sy))
            p.addCurve(to: CGPoint(x: 7 * sx, y: 24 * sy), control1: CGPoint(x: 10 * sx, y: 26 * sy), control2: CGPoint(x: 7 * sx, y: 26 * sy))
            p.addLine(to: CGPoint(x: 7 * sx, y: 8 * sy))
            return p
        }
    }
}

/// FS-R7: Sent → Delivered → Read, each with its time once reached; "Arrives in m:ss" before delivery.
private struct StatusLine: View {
    let letter: LetterFull
    let state: String
    let now: Date

    var body: some View {
        let delivered = state == LetterState.delivered || state == LetterState.read
        let read = state == LetterState.read
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                step("SENT", DLTime.clock(letter.sentAt, now: now), done: true, double: false)
                Rectangle().fill(.dlLine).frame(height: 1).padding(.top, 7)
                step("DELIVERED", delivered ? DLTime.clock(letter.arrivesAt, now: now) : "", done: delivered, double: false)
                Rectangle().fill(.dlLine).frame(height: 1).padding(.top, 7)
                step("READ", read ? DLTime.clock(letter.readAt, now: now) : "", done: read, double: true)
            }
            if !delivered {
                Text(t("letters.arrivesIn", ["countdown": DLTime.countdown(DLTime.remaining(until: letter.arrivesAt, now: now))]))
                    .font(.custom(DLFontName.manropeSemiBold.name, size: 13, relativeTo: .footnote).monospacedDigit())
                    .foregroundStyle(.dlLetterInk)
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(read ? t("letters.status.read") : delivered ? t("letters.status.delivered") : t("letters.status.sent"))
    }

    private func step(_ label: String, _ time: String, done: Bool, double: Bool) -> some View {
        let color: Color = done ? .dlLetterInk : .dlInkQuiet
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if done {
                    Image(systemName: double ? "checkmark.circle" : "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .dlEnter(.pop)
                }
                Text(label).font(.custom(DLFontName.manropeExtraBold.name, size: 11, relativeTo: .caption2)).tracking(0.77)
            }
            if !time.isEmpty {
                Text(time).font(.custom(DLFontName.manropeSemiBold.name, size: 12, relativeTo: .caption))
            }
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}

/// The envelope a NEW letter arrives in: its flap lifts, the seal gives, and it drops away while
/// the sheet rises out of it (web timeline 1100 ms). A tap skips to the sheet.
private struct EnvelopeOpening: View {
    let seal: Color
    let onSkip: () -> Void
    @State private var flap: Double = 0
    @State private var drop: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4).fill(.dlLetterEnvelope)
            ZStack {
                OpeningFlap().fill(.dlLetterFlap)
                OpeningFlap().stroke(.dlLetterEdge, lineWidth: 1)
            }
            .frame(height: 150)
            .rotation3DEffect(.degrees(flap * 88), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
            .opacity(1 - flap)
            WaxSeal(color: seal, size: 30)
                .scaleEffect(1 - 0.4 * flap)
                .opacity(1 - flap)
                .offset(y: 118)
        }
        .frame(height: 260)
        .scaleEffect(1 - 0.04 * drop)
        .offset(y: drop * 70)
        .opacity(1 - drop)
        .onTapGesture(perform: onSkip)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28).delay(0.36)) { flap = 1 }
            withAnimation(.easeIn(duration: 0.48).delay(0.6)) { drop = 1 }
        }
        .accessibilityHidden(true)
    }

    private struct OpeningFlap: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            var p = Path()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.86))
            p.addQuadCurve(to: CGPoint(x: w * 0.43, y: h * 0.86), control: CGPoint(x: w * 0.5, y: h * 0.99))
            p.closeSubpath()
            return p
        }
    }
}
