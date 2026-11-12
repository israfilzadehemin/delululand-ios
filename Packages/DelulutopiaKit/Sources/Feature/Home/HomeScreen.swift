import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

/// S2 Home (web home/HomeScreen.tsx; canvas A-Home): the shared board on top, both moods, the two
/// clocks, From <friend> (new and incoming) and To <friend> (in reach, in transit, delivered and
/// unread), each newest first. Rows flip locally at 0:00 and the screen refetches.
public struct HomeScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlBrand) private var brand
    @State private var actions: HomeActions?

    public init() {}

    public var body: some View {
        let store = backend.home
        Group {
            if let home = store.home, let actions {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HomeContent(home: home, stale: store.offline, now: DLTime.now, actions: actions)
                }
            } else if store.offline {
                VStack {
                    OfflineBanner().padding(.horizontal, 16)
                    Spacer()
                }
            } else {
                HomeLoading()
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(store.home?.universe.name ?? brand)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if actions == nil { actions = HomeActions(backend: backend) }
        }
    }
}

private struct HomeContent: View {
    let home: Home
    let stale: Bool
    let now: Date
    let actions: HomeActions

    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice
    @State private var moodOpen = false
    @State private var cancelId: Int?
    @State private var cancelling = false
    @State private var played = false

    private var friend: Citizen? { home.friend }
    private var first: Int { home.firstCitizen }

    var body: some View {
        let rows = home.from + home.to
        let flipped = rows.contains { LetterState.of($0, now: now) != $0.state }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if stale { OfflineBanner() }
                BoardTile(home: home, now: now, actions: actions)
                VStack(alignment: .leading, spacing: 8) {
                    MyMood(me: home.me, now: now) { moodOpen = true }
                        .dlEnter(.rise)
                    if let friend {
                        FriendCard(friend: friend, now: now) { open(.friend) }
                            .dlEnter(.rise, delay: 0.05)
                    }
                }
                if friend == nil {
                    WaitingCard(name: home.universe.name, isCreator: home.universe.isCreator) { open(.universe) }
                }
                HomeClocks(me: home.me, friend: friend, now: now)
                if home.from.isEmpty, home.to.isEmpty {
                    EmptyPost()
                } else if let friend {
                    if !home.from.isEmpty {
                        GroupHeading(text: "From \(friend.nickname)", who: Who.of(friend.id, first: first))
                        ForEach(Array(home.from.enumerated()), id: \.element.id) { i, row in
                            FromRow(row: row, now: now, who: Who.of(friend.id, first: first))
                                .dlEnter(.rise, delay: played ? 0 : DLMotion.stagger(i))
                        }
                    }
                    if !home.to.isEmpty {
                        GroupHeading(text: "To \(friend.nickname)", who: Who.of(home.me.id, first: first))
                        ForEach(Array(home.to.enumerated()), id: \.element.id) { i, row in
                            ToRow(row: row, now: now, who: Who.of(home.me.id, first: first)) { cancelId = row.id }
                                .dlEnter(.rise, delay: played ? 0 : DLMotion.stagger(i + home.from.count))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .animation(DLMotion.easeOut(0.28), value: rows.map(\.id))
        }
        .scrollDismissesKeyboard(.interactively)
        .environment(\.dlFirstCitizen, first)
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(1))
                played = true
            }
        }
        .onChange(of: flipped) { _, now in if now { actions.flipped() } }
        .sheet(isPresented: $moodOpen) {
            MoodSheet(current: home.me.mood, friend: friend?.nickname, friendMood: friend?.mood, actions: actions) {
                moodOpen = false
            }
            .environment(backend)
        }
        .takeBackDialog(
            isPresented: Binding(get: { cancelId != nil }, set: { if !$0, !cancelling { cancelId = nil } }),
            friend: friend?.nickname ?? "Friend",
            draftEmpty: home.me.draftEmpty
        ) {
            guard let id = cancelId else { return }
            cancelling = true
            Task {
                let result = await actions.cancel(id)
                cancelling = false
                cancelId = nil
                switch result {
                case .done: open(.write(editId: nil))
                case .tooLate: notice(.text(LetterActions.tooLate))
                case .failed: notice(.text(LetterActions.notCancelled))
                }
            }
        }
    }
}

// MARK: - Moods

private struct MyMood: View {
    let me: Citizen
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CitizenAvatar(me, size: 40)
            Button(action: onOpen) {
                Group {
                    if let mood = me.moodText {
                        (Text(mood).font(.custom(DLFontName.manropeBold.rawValue, size: 14, relativeTo: .subheadline)).foregroundColor(.dlInk)
                            + Text(" · set \(ageWords(me.moodSetAt, now: now))")
                            .font(.custom(DLFontName.manropeMedium.rawValue, size: 13, relativeTo: .footnote))
                            .foregroundColor(.dlInkQuiet))
                            .lineLimit(1)
                    } else {
                        Text("Set your mood")
                            .font(.custom(DLFontName.manropeBold.rawValue, size: 14, relativeTo: .subheadline))
                            .foregroundStyle(.dlSeal)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(me.moodText != nil ? Color.dlLetterEnvelope : .clear, in: Capsule())
                .overlay {
                    if me.moodText != nil {
                        Capsule().strokeBorder(.dlLine)
                    } else {
                        DashedOutline(.dlSeal, radius: 20)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(DLPressStyle())
            .accessibilityHint("Change your mood")
        }
    }
}

private struct FriendCard: View {
    let friend: Citizen
    let now: Date
    let onOpen: () -> Void
    @Environment(\.dlFirstCitizen) private var first

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) { CitizenAvatar(friend, size: 48) }
                .buttonStyle(DLPressStyle())
                .accessibilityLabel("\(friend.nickname)’s profile")
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.nickname)
                    .font(.custom(DLFontName.manropeBold.rawValue, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(.dlInk)
                if let mood = friend.moodText {
                    (Text(mood).foregroundColor(.dlInk) + Text(" · set \(ageWords(friend.moodSetAt, now: now))").foregroundColor(.dlInkQuiet))
                        .font(.custom(DLFontName.manropeMedium.rawValue, size: 14, relativeTo: .subheadline))
                } else {
                    Text("No mood yet")
                        .font(.custom(DLFontName.manropeMedium.rawValue, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(.dlInkQuiet)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Who.of(friend.id, first: first).tint, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Universe U8: the friend card's place while the creator is alone.
private struct WaitingCard: View {
    let name: String
    let isCreator: Bool
    let onUniverse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Waiting for someone to join").dlText(.headline).foregroundStyle(.dlInk)
            Text("Send \(name)’s key to the one person you want here.\(isCreator ? " Lost it? Make a new one." : "")")
                .dlText(.callout)
                .foregroundStyle(.dlInk)
            if isCreator {
                Button("You › Universe", action: onUniverse)
                    .buttonStyle(DLButtonStyle(.outline))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(DashedOutline(.dlInkDisabled, radius: 12, width: 2))
    }
}

// MARK: - Clocks (doc "Delululand — Clocks", Board F1)

private struct HomeClocks: View {
    let me: Citizen
    let friend: Citizen?
    let now: Date

    var body: some View {
        if me.timezone != nil, friend == nil || friend?.timezone != nil {
            HStack(spacing: 12) {
                ZoneClock(person: me, now: now)
                if let friend { ZoneClock(person: friend, now: now) } else { Spacer().frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Local times")
        }
    }
}

private struct ZoneClock: View {
    let person: Citizen
    let now: Date
    @Environment(\.dlFirstCitizen) private var first

    var body: some View {
        let zone = person.timezone ?? "UTC"
        let (hour, minute) = DLTime.wallClock(now, zone: zone)
        let night = DLTime.isNight(hour: hour)
        let hhmm = String(format: "%02d:%02d", hour, minute)
        let city = DLTime.city(of: zone)
        HStack(spacing: 10) {
            ClockFace(hour: hour, minute: minute, night: night, ring: Who.of(person.id, first: first).signature)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(person.nickname) · \(city)")
                    .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 13, relativeTo: .footnote))
                    .foregroundStyle(.dlInk)
                    .lineLimit(1)
                (Text(hhmm).foregroundColor(.dlSeal)
                    + Text(night ? " · night" : "").font(.custom(DLFontName.manropeMedium.rawValue, size: 15, relativeTo: .subheadline)).foregroundColor(.dlInkQuiet))
                    .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 15, relativeTo: .subheadline).monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.nickname), \(city): \(hhmm)\(night ? ", night" : "")")
    }
}

/// The analog face on a 100-unit grid (web ClockFace.tsx): ticks, hour and minute hands; navy at night.
private struct ClockFace: View {
    let hour: Int
    let minute: Int
    let night: Bool
    let ring: Color

    var body: some View {
        Canvas { context, size in
            let k = size.width / 100
            context.scaleBy(x: k, y: k)
            let centre = CGPoint(x: 50, y: 50)
            let circle = Path(ellipseIn: CGRect(x: 4, y: 4, width: 92, height: 92))
            context.fill(circle, with: .color(night ? .dlSeal : .dlPaper))
            context.stroke(circle, with: .color(ring), lineWidth: 3)
            for i in 0 ..< 12 {
                let long = i % 3 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: 50, y: long ? 10 : 11.5))
                tick.addLine(to: CGPoint(x: 50, y: long ? 17 : 15))
                let rotated = tick.applying(rotation(Double(i) * 30, around: centre))
                context.stroke(rotated, with: .color(night ? .dlInkOnScrim : .dlInkQuiet), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let hands: Color = night ? .dlPaper : .dlInk
            var h = Path()
            h.move(to: CGPoint(x: 50, y: 54))
            h.addLine(to: CGPoint(x: 50, y: 28))
            context.stroke(h.applying(rotation(Double(hour % 12) * 30 + Double(minute) * 0.5, around: centre)), with: .color(hands), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            var m = Path()
            m.move(to: CGPoint(x: 50, y: 56))
            m.addLine(to: CGPoint(x: 50, y: 18))
            context.stroke(m.applying(rotation(Double(minute) * 6, around: centre)), with: .color(hands), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 47, y: 47, width: 6, height: 6)), with: .color(night ? .dlPaper : .dlSeal))
        }
        .accessibilityHidden(true)
    }

    private func rotation(_ degrees: Double, around c: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y).rotated(by: degrees * .pi / 180).translatedBy(x: -c.x, y: -c.y)
    }
}

// MARK: - Rows

private struct GroupHeading: View {
    let text: String
    let who: Who

    var body: some View {
        Text(text.uppercased())
            .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 11, relativeTo: .caption2))
            .tracking(0.99)
            .foregroundStyle(who == .a ? Color.dlSeal : Color.dlInkQuiet)
            .padding(.top, 4)
            .padding(.leading, 2)
            .accessibilityAddTraits(.isHeader)
            .dlEnter(.fade, delay: 0.06)
    }
}

private struct RowLine: View {
    let text: String
    let strong: Bool

    var body: some View {
        Text(text)
            .font(.custom(strong ? DLFontName.manropeBold.rawValue : DLFontName.manropeMedium.rawValue, size: 15, relativeTo: .subheadline))
            .foregroundStyle(.dlLetterInk)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

private struct RowMeta: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.custom(DLFontName.manropeMedium.rawValue, size: 13, relativeTo: .footnote))
            .foregroundStyle(.dlInkQuiet)
    }
}

private struct InTransit: View {
    let row: LetterRow
    let now: Date
    let who: Who
    let arrives: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                RowMeta(text: "On its way · arrives \(arrives)")
                LetterArc(progress: travelled(row, now: now), who: who)
            }
            Text(DLTime.countdown(DLTime.remaining(until: row.arrivesAt, now: now)))
                .dlText(.countdown)
                .foregroundStyle(.dlLetterInk)
        }
    }
}

/// From the friend: NEW once arrived (opens the letter), else an incoming row that opens nothing (FS-R3).
private struct FromRow: View {
    let row: LetterRow
    let now: Date
    let who: Who
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice

    var body: some View {
        let state = LetterState.of(row, now: now)
        let arrives = DLTime.clock(row.arrivesAt, now: now)
        if state == LetterState.delivered || state == LetterState.read {
            Button { open(.letter(row.id)) } label: {
                LetterTile(tileShapeOf(row, state: state), who: who) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            RowLine(text: firstLineOf(row), strong: true)
                            RowMeta(text: "Arrived \(DLTime.clock(row.arrivesAt, now: now))")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let stamp = row.stamp { RowStamp(stamp, id: row.id) }
                        if state == LetterState.delivered { NewChip() }
                    }
                }
            }
            .buttonStyle(DLPressStyle(scale: 0.99))
        } else {
            Button { notice(.text("Arrives at \(arrives)")) } label: {
                LetterTile(.envelope, who: who) { InTransit(row: row, now: now, who: who, arrives: arrives) }
            }
            .buttonStyle(DLPressStyle(scale: 0.99))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("On its way, arrives \(arrives)")
        }
    }
}

/// To the friend: in reach (Edit, Cancel), in transit (arc and countdown), delivered and not read yet.
private struct ToRow: View {
    let row: LetterRow
    let now: Date
    let who: Who
    let onCancel: () -> Void
    @Environment(\.dlOpen) private var open

    var body: some View {
        let state = LetterState.of(row, now: now)
        let arrives = DLTime.clock(row.arrivesAt, now: now)
        switch state {
        case LetterState.inReach:
            LetterTile(.envelope, who: who, reach: true) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(DLTime.countdown(DLTime.remaining(until: row.windowEndsAt, now: now))) left to edit or cancel")
                        .font(.custom(DLFontName.manropeBold.rawValue, size: 13, relativeTo: .footnote).monospacedDigit())
                        .foregroundStyle(.dlLetterInk)
                    Spacer(minLength: 8)
                    RowMeta(text: "Arrives \(arrives)")
                }
                Button { open(.letter(row.id)) } label: {
                    HStack(spacing: 8) {
                        RowLine(text: firstLineOf(row), strong: false).frame(maxWidth: .infinity, alignment: .leading)
                        if let stamp = row.stamp { RowStamp(stamp, id: row.id, width: 24) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    ReachButton("Edit") { open(.write(editId: row.id)) }
                    ReachButton("Cancel", action: onCancel)
                }
            }
        case LetterState.inTransit:
            Button { open(.letter(row.id)) } label: {
                LetterTile(.envelope, who: who) { InTransit(row: row, now: now, who: who, arrives: arrives) }
            }
            .buttonStyle(DLPressStyle(scale: 0.99))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("On its way, arrives \(arrives)")
        default:
            Button { open(.letter(row.id)) } label: {
                LetterTile(.sheet, who: who) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            RowLine(text: firstLineOf(row), strong: false)
                            RowMeta(text: state == LetterState.read
                                ? "Read \(DLTime.clock(row.readAt, now: now))"
                                : "Delivered \(DLTime.clock(row.arrivesAt, now: now)) · not read yet")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let stamp = row.stamp { RowStamp(stamp, id: row.id, width: 24) }
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.dlInkQuiet)
                    }
                }
            }
            .buttonStyle(DLPressStyle(scale: 0.99))
        }
    }
}

/// Nothing in the post yet: the empty envelope with its plus seal.
private struct EmptyPost: View {
    var body: some View {
        VStack(spacing: 16) {
            Canvas { context, size in
                context.scaleBy(x: size.width / 96, y: size.height / 72)
                let body = Path(roundedRect: CGRect(x: 8, y: 14, width: 80, height: 50), cornerRadius: 6)
                context.fill(body, with: .color(.dlLetterSheet))
                context.stroke(body, with: .color(.dlLine), lineWidth: 1.5)
                var v = Path()
                v.move(to: CGPoint(x: 8, y: 20))
                v.addLine(to: CGPoint(x: 48, y: 46))
                v.addLine(to: CGPoint(x: 88, y: 20))
                context.stroke(v, with: .color(.dlLine), lineWidth: 1.5)
                let seal = Path(ellipseIn: CGRect(x: 69, y: 9, width: 18, height: 18))
                context.fill(seal, with: .color(.dlPaper))
                context.stroke(seal, with: .color(.dlPostmarkHue), lineWidth: 1.5)
                var plus = Path()
                plus.move(to: CGPoint(x: 78, y: 13))
                plus.addLine(to: CGPoint(x: 78, y: 23))
                plus.move(to: CGPoint(x: 73, y: 18))
                plus.addLine(to: CGPoint(x: 83, y: 18))
                context.stroke(plus, with: .color(.dlPostmarkHue), lineWidth: 1.5)
            }
            .frame(width: 96, height: 72)
            .dlEnter(.rise)
            .accessibilityHidden(true)
            Text("Nothing in the post yet")
                .dlText(.subheadline)
                .foregroundStyle(.dlInkQuiet)
                .dlEnter(.rise, delay: 0.08)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }
}

/// S2-Home-loading: placeholders in the shapes that will arrive.
private struct HomeLoading: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 6).fill(.dlLetterEnvelope).aspectRatio(4 / 3, contentMode: .fit)
                HStack(spacing: 10) {
                    Circle().fill(.dlLetterEnvelope).frame(width: 40, height: 40)
                    Capsule().fill(.dlLetterEnvelope).frame(width: 140, height: 40)
                }
                RoundedRectangle(cornerRadius: 16).fill(.dlLetterEnvelope).frame(height: 68)
                ForEach(0 ..< 3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(.dlLetterEnvelope).frame(height: 64)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollDisabled(true)
        .accessibilityLabel("Loading")
    }
}
