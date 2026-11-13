import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI

/// S6 Letters (FS-R11, FS-R12; web letters/LettersScreen.tsx; canvas C-Letters, C-Letters-list):
/// every letter both ways, newest first, 20 per page by keyset. Two-column thumbnails (the default)
/// or rows; the glass pair at the top-right flips the layout (remembered on this device) and
/// writes. Pull to refresh (I-4).
public struct LettersScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open

    public init() {}

    public var body: some View {
        let store = backend.letters
        let list = backend.settings.lettersList
        let me = backend.home.home?.me
        let draft = me?.draftEmpty == false
        Group {
            if !store.loaded {
                LettersLoading(list: list)
            } else if store.rows.isEmpty, !store.hasMore {
                EmptyLetters(draft: draft) { open(.write(editId: nil)) }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LettersContent(store: store, list: list, now: DLTime.now)
                }
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(t("letters.letters"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    backend.settings.setLettersList(!list)
                } label: {
                    Image(systemName: list ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(list ? t("letters.showAsThumbnails") : t("letters.showAsList"))
                Button {
                    open(.write(editId: nil))
                } label: {
                    Image(systemName: "square.and.pencil")
                        .overlay(alignment: .topTrailing) {
                            if draft { DLNewDot().offset(x: 4, y: -2) }
                        }
                }
                .accessibilityLabel(draft ? t("letters.continueYourDraft") : t("letters.writeALetter"))
            }
        }
        .refreshable { await store.loadHead() }
        .onAppear { store.attach() }
        .onDisappear { store.detach() }
    }
}

private struct LettersContent: View {
    let store: LettersStore
    let list: Bool
    let now: Date

    @Environment(Backend.self) private var backend
    @State private var played = false

    var body: some View {
        let rows = store.rows
        let home = backend.home.home
        let friendName = home?.friend?.nickname ?? t("common.friend")
        let first = home?.firstCitizen
        let senderOf = { (row: LetterRow) -> Int in row.isMine ? (home?.me.id ?? 1) : (home?.friend?.id ?? 2) }
        ScrollView {
            LazyVStack(spacing: list ? 8 : 14) {
                if list {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        ListRow(row: row, now: now, friendName: friendName, who: Who.of(senderOf(row), first: first))
                            .dlEnter(.rise, delay: played ? 0 : DLMotion.stagger(i))
                            .onAppear { if i >= rows.count - 3 { store.loadMore() } }
                    }
                } else {
                    let pairs = stride(from: 0, to: rows.count, by: 2).map { Array(rows[$0 ..< min($0 + 2, rows.count)]) }
                    ForEach(Array(pairs.enumerated()), id: \.element.first!.id) { i, pair in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(pair.enumerated()), id: \.element.id) { j, row in
                                Thumb(row: row, now: now, friendName: friendName, who: Who.of(senderOf(row), first: first), index: i * 2 + j)
                                    .dlEnter(.rise, delay: played ? 0 : DLMotion.stagger(i * 2 + j))
                            }
                            if pair.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                        .onAppear { if i * 2 >= rows.count - 4 { store.loadMore() } }
                    }
                }
                HStack(spacing: 8) {
                    if store.hasMore {
                        ProgressView().controlSize(.small)
                        Text(t("letters.loadingOlder"))
                    } else {
                        Text(t("common.thatIsEverything"))
                    }
                }
                .dlText(.footnote)
                .foregroundStyle(.dlInkQuiet)
                .frame(minHeight: 40)
                .dlEnter(.fade)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .environment(\.dlFirstCitizen, first)
        .task {
            try? await Task.sleep(for: .seconds(1))
            played = true
        }
    }
}

private func arrivedOf(_ state: String) -> Bool { state == LetterState.delivered || state == LetterState.read }

private struct Direction: View {
    let text: String
    let who: Who

    var body: some View {
        Text(text.uppercased())
            .font(.custom(DLFontName.manropeExtraBold.name, size: 11, relativeTo: .caption2))
            .tracking(0.77)
            .foregroundStyle(who == .a ? Color.dlInk : Color.dlInkQuiet)
            .lineLimit(1)
    }
}

/// The state shared by rows and tiles (FS-R11): in reach, countdown, NEW, Opened, Read, Delivered.
struct StatusChip: View {
    let row: LetterRow
    let state: String
    let now: Date

    var body: some View {
        let to = row.isMine
        let small = Font.custom(DLFontName.manropeSemiBold.name, size: 12, relativeTo: .caption)
        if to, state == LetterState.inReach {
            Text(t("letters.toEdit", ["countdown": DLTime.countdown(DLTime.remaining(until: row.windowEndsAt, now: now))]))
                .font(.custom(DLFontName.manropeExtraBold.name, size: 12, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(.dlLetterInk)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(.dlCountdownChip, in: Capsule())
        } else if !arrivedOf(state) {
            Text(DLTime.countdown(DLTime.remaining(until: row.arrivesAt, now: now)))
                .font(.custom(DLFontName.manropeExtraBold.name, size: 18, relativeTo: .headline).monospacedDigit())
                .foregroundStyle(.dlLetterInk)
        } else if !to, state == LetterState.delivered {
            NewChip()
        } else if !to {
            Text(t("letters.opened", ["time": DLTime.clock(row.readAt, now: now)])).font(small).foregroundStyle(.dlInkQuiet)
        } else if state == LetterState.read {
            Label(t("letters.readAt", ["time": DLTime.clock(row.readAt, now: now)]), systemImage: "checkmark.circle")
                .font(small).foregroundStyle(.dlInkQuiet).labelStyle(TightLabel())
        } else {
            Label(t("letters.delivered"), systemImage: "checkmark").font(small).foregroundStyle(.dlInkQuiet).labelStyle(TightLabel())
        }
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Replies B2: the row's letter answers another one.
private struct ReplyMark: View {
    var body: some View {
        Text("↰").foregroundStyle(.dlInkQuiet).accessibilityLabel(t("letters.replyMark"))
    }
}

private struct ListRow: View {
    let row: LetterRow
    let now: Date
    let friendName: String
    let who: Who
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice

    var body: some View {
        let state = LetterState.of(row, now: now)
        let arrived = arrivedOf(state)
        let to = row.isMine
        let incoming = !to && !arrived
        let isNew = !to && state == LetterState.delivered
        let arrives = DLTime.clock(row.arrivesAt, now: now)
        Button {
            if incoming { notice(.text(t("letters.arrivesAt", ["time": arrives]))) } else { open(.letter(row.id)) }
        } label: {
            LetterTile(tileShapeOf(row, state: state), who: who) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Direction(text: to ? t("letters.toFriend", ["friend": friendName]) : t("letters.fromFriend", ["friend": friendName]), who: who)
                        HStack(spacing: 4) {
                            if !incoming, row.replyToId != nil { ReplyMark() }
                            Text(incoming ? t("letters.onItsWay") : firstLineOf(row))
                                .font(.custom(isNew ? DLFontName.manropeBold.name : DLFontName.manropeMedium.name, size: 15, relativeTo: .subheadline))
                                .foregroundStyle(incoming ? Color.dlInkQuiet : Color.dlLetterInk)
                                .lineLimit(1)
                                .ownText(incoming ? "" : row.firstLine ?? "")
                        }
                        Text(arrived ? t("letters.timesArrived", ["sent": DLTime.clock(row.sentAt, now: now), "arrived": arrives]) : t("letters.timesArrives", ["sent": DLTime.clock(row.sentAt, now: now), "arrives": arrives]))
                            .font(.custom(DLFontName.manropeMedium.name, size: 12, relativeTo: .caption))
                            .foregroundStyle(.dlInkQuiet)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let stamp = row.stamp { RowStamp(stamp, id: row.id) }
                    StatusChip(row: row, state: state, now: now)
                }
            }
        }
        .buttonStyle(DLPressStyle(scale: 0.99))
    }
}

private let tilts: [Double] = [-0.7, 0.6, 0.5, -0.5]

/// One letter as a thumbnail (canvas C-Letters): an envelope (flap, wax seal, a postmark across the
/// stamp) or a letter sheet (margin, ruled lines, a folded corner). Nothing of an incoming letter
/// shows before it arrives; tapping it only repeats the ETA.
private struct Thumb: View {
    let row: LetterRow
    let now: Date
    let friendName: String
    let who: Who
    let index: Int
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice

    var body: some View {
        let state = LetterState.of(row, now: now)
        let arrived = arrivedOf(state)
        let to = row.isMine
        let incoming = !to && !arrived
        let isNew = !to && state == LetterState.delivered
        let shape = tileShapeOf(row, state: state)
        let media = incoming ? nil : row.media
        let envelope = shape == .envelope
        Button {
            if incoming { notice(.text(t("letters.arrivesAt", ["time": DLTime.clock(row.arrivesAt, now: now)]))) } else { open(.letter(row.id)) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Direction(text: to ? t("letters.toFriend", ["friend": friendName]) : t("letters.fromFriend", ["friend": friendName]), who: who)
                    .padding(.trailing, envelope ? 0 : 30)
                (Text(!incoming && row.replyToId != nil ? "↰ " : "").foregroundColor(.dlInkQuiet)
                    + Text(incoming ? t("letters.onItsWay") : firstLineOf(row)))
                    .font(.custom(isNew ? DLFontName.literataBold.name : DLFontName.literataRegular.name, size: 15, relativeTo: .body))
                    .lineSpacing(envelope ? 1 : 0)
                    .foregroundStyle(incoming ? Color.dlInkQuiet : Color.dlLetterInk)
                    .lineLimit(envelope ? 2 : 3)
                    .ownText(incoming ? "" : row.firstLine ?? "")
                    .padding(.trailing, envelope ? 0 : 22)
                    .background(alignment: .top) { if !envelope { Rules() } }
                if let media, media.photos + media.audios + media.doodles > 0 {
                    HStack(spacing: 8) {
                        if media.photos > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "photo")
                                Text("\(media.photos)")
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(tn("letters.photos", media.photos))
                        }
                        if media.audios > 0 { Image(systemName: "mic").accessibilityLabel(t("letters.preview.voiceNote")) }
                        if media.doodles > 0 { Image(systemName: "scribble").accessibilityLabel(t("letters.doodle")) }
                    }
                    .font(.custom(DLFontName.manropeSemiBold.name, size: 12, relativeTo: .caption))
                    .foregroundStyle(.dlInkQuiet)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("letters.sent", ["time": DLTime.clock(row.sentAt, now: now)]))
                        .font(.custom(DLFontName.manropeMedium.name, size: 12, relativeTo: .caption))
                        .foregroundStyle(.dlInkQuiet)
                    StatusChip(row: row, state: state, now: now)
                }
            }
            .padding(envelope ? EdgeInsets(top: 78, leading: 12, bottom: 12, trailing: 12) : EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .top) {
                if envelope { ThumbFlap(seal: who.signature) }
            }
            .background(alignment: .leading) {
                if !envelope { Rectangle().fill(.dlLetterMargin).frame(width: 1).padding(.leading, 9) }
            }
            .overlay(on: .topRight) {
                if let stamp = row.stamp {
                    HStack(spacing: -8) {
                        if envelope { Postmark().frame(width: 30, height: 30).opacity(0.55) }
                        StampImage(url: stamp.imageUrl, name: stamp.name, width: 26)
                            .rotationEffect(.degrees(3))
                            .shadow(color: .dlShade.opacity(0.25), radius: 0.5, y: 1)
                    }
                    .padding(.top, envelope ? 10 : 8)
                    .padding(.trailing, 10)
                }
            }
            .overlay(on: .bottomRight) { if !envelope { DogEar().scaleEffect(16 / 14, anchor: .bottomTrailing) } }
            .background(envelope ? Color.dlLetterEnvelope : Color.dlLetterSheet, in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.dlLetterInk.opacity(0.22), lineWidth: 0.5))
            .shadow(color: .dlShade.opacity(0.12), radius: 1.5, y: 1)
            .rotationEffect(.degrees(tilts[index % 4]))
        }
        .buttonStyle(DLPressStyle(scale: 0.98))
        .frame(maxWidth: .infinity)
    }
}

/// The thumbnail's flap (viewBox 100 × 40, 56 pt tall) and its 22 pt seal.
private struct ThumbFlap: View {
    let seal: Color

    var body: some View {
        ZStack(alignment: .top) {
            FlapStroke(closed: true).fill(.dlLetterFlap).frame(height: 56)
            FlapStroke(closed: false).stroke(.dlLetterEdge, lineWidth: 0.6).frame(height: 56)
            WaxSeal(color: seal, size: 22).offset(y: 44)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private struct FlapStroke: Shape {
        let closed: Bool

        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: rect.midX, y: rect.height * 38 / 40))
            p.addLine(to: CGPoint(x: rect.maxX, y: 0))
            if closed { p.closeSubpath() }
            return p
        }
    }
}

/// A sage postmark across the stamp: two rings and three waves (web .dl-postmark).
struct Postmark: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 48, y: size.height / 48)
            let hue = GraphicsContext.Shading.color(.dlPostmarkHue)
            context.stroke(Path(ellipseIn: CGRect(x: 4, y: 4, width: 40, height: 40)), with: hue, lineWidth: 1.5)
            context.stroke(Path(ellipseIn: CGRect(x: 9, y: 9, width: 30, height: 30)), with: hue, lineWidth: 1)
            context.stroke(PathData.path("M2 20c8-3 14 3 22 0s14 3 22 0M2 28c8-3 14 3 22 0s14 3 22 0"), with: hue, lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}

/// The ruled lines under a sheet tile's text (19 pt apart).
private struct Rules: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 18
            while y < size.height + 19 * 3 {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.dlLetterRule))
                y += 19
            }
        }
        .frame(height: 19 * 3)
        .accessibilityHidden(true)
    }
}

private struct LettersLoading: View {
    let list: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(.dlLetterEnvelope).frame(height: list ? 72 : 176)
                }
            }
            .padding(16)
        }
        .scrollDisabled(true)
        .accessibilityLabel(t("letters.loading"))
    }
}

private struct EmptyLetters: View {
    let draft: Bool
    let onWrite: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Canvas { context, size in
                context.scaleBy(x: size.width / 120, y: size.height / 96)
                let body = Path(roundedRect: CGRect(x: 14, y: 30, width: 92, height: 58), cornerRadius: 6)
                context.fill(body, with: .color(.dlLetterSheet))
                context.stroke(body, with: .color(.dlLine), lineWidth: 1.5)
                context.stroke(PathData.path("M14 36 L60 66 L106 36"), with: .color(.dlLine), lineWidth: 1.5)
                let plane = PathData.path("M60 8 L94 28 L74 36 L68 50 Z")
                context.fill(plane, with: .color(.dlSealTint))
                context.stroke(plane, with: .color(.dlSeal), lineWidth: 1.5)
            }
            .frame(width: 120, height: 96)
            .dlEnter(.rise)
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(t("letters.noLettersYet")).dlText(.headline).foregroundStyle(.dlInk)
                Text(t("letters.writeTheFirstOne")).dlText(.subheadline).foregroundStyle(.dlInkQuiet)
            }
            .dlEnter(.rise, delay: 0.08)
            Button(draft ? t("letters.continueYourDraft") : t("letters.writeALetter"), action: onWrite)
                .buttonStyle(DLButtonStyle(.filled))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
