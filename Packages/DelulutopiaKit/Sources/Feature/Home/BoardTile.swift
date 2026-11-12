import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

private let commentMax = 140
private let countFrom = 120

private func commentLength(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ").unicodeScalars.count
}

private struct Pending {
    let png: Data
    let current: Board
    let edit: Bool
}

private enum PadMode: String, Identifiable {
    case new, edit
    var id: String { rawValue }
}

/// The shared board (web board/BoardTile.tsx, doc "Delululand — Board"; canvas A-Home-board): a
/// whiteboard at the top of Home holding the one doodle alive, which either citizen replaces (B1,
/// B11). Tap it to see it full screen (B8); Draw opens the pad on a blank 4:3 surface (B3, B5); a
/// post over a doodle that changed meanwhile asks first (B10). The friend's new doodle carries NEW
/// until Home has shown it (B12). Reactions (§R), Edit (§E) and the friend's sticky note (§C).
/// Folds to a strip (§9).
struct BoardTile: View {
    let home: Home
    let now: Date
    let actions: HomeActions

    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @Environment(\.dlFirstCitizen) private var first
    @State private var pad: PadMode?
    @State private var viewing = false
    @State private var busy = false
    @State private var conflict: Pending?
    @State private var picking = false
    @State private var drawn: String?
    @State private var ribbon: Int?

    private var board: Board? { home.board }
    private var friend: String { home.friendName }
    private var mini: Bool { backend.settings.boardMini }
    private var canReact: Bool { board.map { $0.authorId != home.me.id } ?? false }
    private var mark: BoardReaction? { BoardReaction.of(board?.reaction) }
    private var whose: String? { board.map { $0.authorId == home.me.id ? "your doodle" : "\(friend)’s doodle" } }

    private func nameOf(_ authorId: Int) -> String { authorId == home.me.id ? "You" : friend }

    private func didWhat(_ b: Board) -> String {
        guard let from = b.editedFrom else { return "drew this" }
        if from == b.authorId { return "edited this" }
        return "edited \(from == home.me.id ? "your" : "\(friend)’s") doodle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mini {
                strip
            } else if let board {
                unfolded(board)
            } else {
                empty
            }
        }
        .animation(DLMotion.easeOut(0.28), value: mini)
        .onAppear { markRibbon() }
        .onChange(of: board?.version) { _, _ in markRibbon() }
        .onChange(of: mini) { _, _ in markRibbon() }
        .fullScreenCover(isPresented: $viewing) {
            if let board {
                BoardViewer(board: board, home: home, actions: actions, canReact: canReact, onReact: {
                    picking = true
                }, onClose: { viewing = false }, onDraw: { mode in
                    viewing = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        pad = mode == "edit" ? .edit : .new
                    }
                })
                .environment(backend)
                .environment(\.dlFirstCitizen, first)
                .environment(\.dlNotice, notice)
                .sheet(isPresented: $picking) { reactSheet(board) }
            }
        }
        .fullScreenCover(item: $pad) { mode in
            let edit = mode == .edit && board != nil
            DoodlePad(
                surface: .board,
                title: edit ? "Edit the board" : "Draw on the board",
                doneLabel: "Post",
                busyLabel: "Posting…",
                busy: busy,
                note: whose.map { edit ? "Posting replaces \($0) with your edit" : "Posting replaces \($0)" },
                backdrop: edit ? board?.url : nil,
                onDone: { png in post(png, version: board?.version ?? 0, edit: edit) },
                onClose: {
                    conflict = nil
                    pad = nil
                },
                onBackdropError: {
                    pad = nil
                    notice(.text("Couldn’t open the doodle. Try again."))
                }
            )
            .environment(backend)
            .alert(conflictTitle, isPresented: conflictShown) {
                Button(conflictKeep, role: .cancel) {
                    conflict = nil
                    pad = nil
                }
                Button("Replace it") {
                    if let c = conflict { post(c.png, version: c.current.version, edit: c.edit) }
                }
            } message: {
                Text("You were drawing over an older one. Posting now replaces it; keeping it discards your drawing.")
            }
        }
        .sheet(isPresented: Binding(get: { picking && !viewing }, set: { picking = $0 })) {
            if let board { reactSheet(board) }
        }
    }

    private func markRibbon() {
        guard let board, home.boardNew else { return }
        if ribbon != board.version { ribbon = board.version }
        if !mini { actions.boardSeen(board.version) }
    }

    // MARK: Writes

    private func post(_ png: Data, version: Int, edit: Bool) {
        busy = true
        Task {
            switch await actions.postBoard(png: png, baseVersion: version, edit: edit) {
            case .posted:
                ribbon = nil
                conflict = nil
                pad = nil
            case let .conflict(current):
                conflict = Pending(png: png, current: current, edit: edit)
            case let .failed(text):
                notice(.text(text))
            }
            busy = false
        }
    }

    private func react(_ key: String?) {
        picking = false
        guard let board, key != board.reaction else { return }
        drawn = key.map { "\(board.version):\($0)" }
        Task {
            if let text = await actions.react(board, key: key, friend: friend) { notice(.text(text)) }
        }
    }

    private var conflictShown: Binding<Bool> {
        Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })
    }

    private var conflictMine: Bool { conflict?.current.authorId == home.me.id }
    private var conflictTitle: String { "\(conflictMine ? "You" : friend) just posted a new doodle" }
    private var conflictKeep: String { conflictMine ? "Keep it" : "Keep \(friend)’s" }

    // MARK: Pieces

    private func unfolded(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button { viewing = true } label: {
                    BoardFrame {
                        ZStack(alignment: .topLeading) {
                            BoardImage(url: board.url)
                            if ribbon == board.version {
                                NewChip(paper: false).padding(8)
                            }
                        }
                    }
                }
                .buttonStyle(DLPressStyle(scale: 0.99))
                .accessibilityLabel("Board: \(board.authorId == home.me.id ? "your" : "\(friend)’s") doodle. Open full screen")
                corner(board).padding(13)
            }
            BoardNote(board: board, home: home, actions: actions)
            HStack(spacing: 10) {
                WhoDot(color: Who.of(board.authorId, first: first).signature)
                let reacted = board.reaction == nil ? "" : (canReact ? " · you reacted" : " · \(friend) reacted")
                (Text(nameOf(board.authorId)).font(DLTextStyle.footnoteStrong.spec.dynamicFont).foregroundColor(.dlInk)
                    + Text(" \(didWhat(board)) · \(ageWords(board.createdAt, now: now))\(reacted)"))
                    .font(DLTextStyle.footnote.spec.dynamicFont)
                    .foregroundStyle(.dlInkQuiet)
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
            .padding(.top, 4)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                DrawButton(symbol: "pencil", title: "Edit", label: whose.map { "Edit \($0)" }) { pad = .edit }
                DrawButton(symbol: "scribble", title: "Draw", label: nil) { pad = .new }
                FoldButton(up: true) { backend.settings.setBoardMini(true) }
                    .padding(.trailing, -8)
            }
        }
    }

    @ViewBuilder
    private func corner(_ board: Board) -> some View {
        if canReact {
            Button { picking = true } label: {
                Group {
                    if let mark {
                        HandReaction(reaction: mark, size: 44, draw: drawn == "\(board.version):\(mark.key)")
                    } else {
                        ReactSlot()
                    }
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .rotationEffect(.degrees(mark == nil ? 0 : 8))
            .accessibilityLabel(mark.map { "Your reaction: \($0.name). Change it" } ?? "React to \(friend)’s doodle")
        } else if let mark {
            HandReaction(reaction: mark, size: 44, tilt: 8, label: "\(friend) reacted: \(mark.name)")
                .frame(width: 48, height: 48)
        }
    }

    private var empty: some View {
        ZStack(alignment: .bottomTrailing) {
            BoardFrame {
                VStack(spacing: 14) {
                    Text("The board is empty")
                        .font(.custom(DLFontName.literataRegular.rawValue, size: 17, relativeTo: .body))
                        .foregroundStyle(Ink.slate)
                    Button { pad = .new } label: {
                        Label("Draw the first doodle", systemImage: "scribble")
                    }
                    .buttonStyle(DLButtonStyle(.filled))
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            FoldButton(up: true) { backend.settings.setBoardMini(true) }
                .offset(y: 8)
        }
    }

    /// §9: the folded strip, with NEW while unseen.
    private var strip: some View {
        Button { backend.settings.setBoardMini(false) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Color.dlBoardSurface
                    if let board { BoardImage(url: board.url) }
                }
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Board").font(.custom(DLFontName.manropeExtraBold.rawValue, size: 15, relativeTo: .subheadline))
                        if home.boardNew, board != nil { NewChip(paper: false) }
                    }
                    Text(board.map { "\(nameOf($0.authorId)) \($0.editedFrom == nil ? "drew" : "edited") · \(ageWords($0.createdAt, now: now))" } ?? "The board is empty")
                        .font(DLTextStyle.footnote.spec.dynamicFont)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Ink.navy)
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12))
            .background(.dlBoardFrame, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
            .shadow(color: .dlShade.opacity(0.18), radius: 1.5, y: 1)
        }
        .buttonStyle(DLPressStyle(scale: 0.99))
        .accessibilityHint("Unfold the board")
    }

    private func reactSheet(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("React to \(friend)’s doodle").dlText(.title3).foregroundStyle(.dlInk)
                Spacer()
                DLGlassIconButton("xmark", label: "Close") { picking = false }
            }
            .padding(.horizontal, 8)
            VStack(spacing: 6) {
                ForEach(0 ..< 2, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(BoardReaction.all[row * 5 ..< row * 5 + 5]) { r in
                            let on = board.reaction == r.key
                            Button { react(r.key) } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        if on { ChosenRing(color: Ink.ink) }
                                        HandReaction(reaction: r, size: 44)
                                    }
                                    .frame(width: 56, height: 56)
                                    Text(r.name)
                                        .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 12, relativeTo: .caption))
                                        .foregroundStyle(Ink.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(DLPressStyle())
                            .accessibilityLabel(r.name)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .background(Color(red: 0xFB / 255, green: 0xFB / 255, blue: 0xF8 / 255), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.dlBoardFrame, lineWidth: 4))
            if board.reaction != nil {
                Button("Remove reaction") { react(nil) }
                    .buttonStyle(DLButtonStyle(.outline, fullWidth: true))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .presentationDetents([.height(board.reaction == nil ? 330 : 390)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.dlSheet)
    }
}

/// The doodle image itself, fitted to the 4:3 surface.
struct BoardImage: View {
    let url: String

    var body: some View {
        RemoteImage(url, contentMode: .fit, maxPixel: 1024) { Color.clear }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

struct WhoDot: View {
    let color: Color

    var body: some View {
        Circle().strokeBorder(color, lineWidth: 3).frame(width: 14, height: 14)
    }
}

/// Edit and Draw (web .dl-outline-btn with an icon): 40 pt, navy outline, 14/800.
private struct DrawButton: View {
    let symbol: String
    let title: String
    let label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                Text(title).font(.custom(DLFontName.manropeExtraBold.rawValue, size: 14, relativeTo: .subheadline))
            }
            .foregroundStyle(.dlSeal)
            .padding(.horizontal, 22)
            .frame(height: 40)
            .overlay(Capsule().strokeBorder(.dlSeal, lineWidth: 1.5))
            .contentShape(Capsule())
            .frame(minHeight: 44)
        }
        .buttonStyle(DLPressStyle())
        .accessibilityLabel(label ?? title)
    }
}

private struct FoldButton: View {
    let up: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.dlInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up ? "Fold the board" : "Unfold the board")
    }
}

/// The board comment (§C): one handwritten sticky note taped under the tray. Only the friend of
/// the doodle's author writes it, once; it can be deleted (not edited) and written again.
struct BoardNote: View {
    let board: Board
    let home: Home
    let actions: HomeActions
    var viewer = false

    @Environment(\.dlNotice) private var notice
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    private var friend: String { home.friendName }
    private var mine: Bool { board.authorId != home.me.id }
    private var dark: Bool { scheme == .dark }
    private var face: Color { dark ? Color(red: 0x4F / 255, green: 0x4A / 255, blue: 0x2C / 255) : Color(red: 0xF6 / 255, green: 0xEA / 255, blue: 0xB0 / 255) }
    private var deep: Color { dark ? Color(red: 0x45 / 255, green: 0x40 / 255, blue: 0x2A / 255) : Color(red: 0xEC / 255, green: 0xDC / 255, blue: 0x93 / 255) }
    private var ink: Color { dark ? Color(red: 0xEC / 255, green: 0xE4 / 255, blue: 0xD6 / 255) : Ink.ink }
    private var tape: Color { dark ? Color(red: 0x78 / 255, green: 0x70 / 255, blue: 0x62 / 255).opacity(0.7) : Color(red: 0xEC / 255, green: 0xE4 / 255, blue: 0xD2 / 255).opacity(0.78) }

    private func caveat(_ size: CGFloat) -> Font { .custom(DLFontName.caveatMedium.rawValue, size: size, relativeTo: .body) }

    var body: some View {
        if board.comment != nil || mine {
            FractionWidth(fraction: 0.78, maxWidth: 340, leading: viewer ? 0 : 22) {
                note.rotationEffect(.degrees(-1.5), anchor: .top)
            }
            .padding(.top, -12)
            .zIndex(3)
            .onChange(of: board.version) { _, _ in text = "" }
        }
    }

    @ViewBuilder
    private var note: some View {
        ZStack(alignment: .top) {
            if let comment = board.comment {
                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.text).font(caveat(23)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                    Text("— \(mine ? "You" : friend)")
                        .font(caveat(18))
                        .foregroundStyle(ink.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 10, trailing: 40))
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(LinearGradient(stops: [.init(color: face, location: 0.7), .init(color: deep, location: 1)], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .shadow(color: .black.opacity(0.08), radius: 0.5, y: 1)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 6)
                .overlay(alignment: .topTrailing) {
                    if mine {
                        Button {
                            guard !busy else { return }
                            busy = true
                            Task {
                                if let failed = await actions.uncomment(board, friend: friend) { notice(.text(failed)) }
                                busy = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ink)
                                .frame(width: 28, height: 28)
                                .background(ink.opacity(0.08), in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                        .disabled(busy)
                        .accessibilityLabel("Delete your comment")
                    }
                }
            } else {
                composer
            }
            Rectangle().fill(tape).frame(width: 64, height: 18).rotationEffect(.degrees(2)).offset(y: -9)
                .accessibilityHidden(true)
        }
    }

    private var composer: some View {
        let length = commentLength(text)
        let tooLong = length > commentMax
        let enabled = !busy && length > 0 && !tooLong
        return HStack(spacing: 6) {
            TextField("", text: $text, prompt: Text("Leave \(friend) a note…").foregroundColor(ink.opacity(0.55)))
                .font(caveat(21))
                .foregroundStyle(ink)
                .tint(ink)
                .submitLabel(.send)
                .focused($focused)
                .disabled(busy)
                .onSubmit { submit(enabled) }
                .onChange(of: text) { _, value in
                    let one = value.replacingOccurrences(of: "\n", with: " ")
                    if one != value { text = one }
                }
                .accessibilityLabel("Comment on \(friend)’s doodle")
            if length >= countFrom {
                Text("\(commentMax - length)")
                    .font(DLTextStyle.footnote.spec.dynamicFont)
                    .foregroundStyle(tooLong ? Color.dlError : ink.opacity(0.7))
            }
            Button { submit(enabled) } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.dlSeal.opacity(enabled ? 1 : 0.35), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel("Post comment")
        }
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 4))
        .frame(minHeight: 56)
        .background(face.opacity(0.55), in: RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(deep, lineWidth: 1.5))
    }

    private func submit(_ enabled: Bool) {
        guard enabled else { return }
        busy = true
        Task {
            if let failed = await actions.comment(board, text: text, friend: friend) {
                notice(.text(failed))
            } else {
                text = ""
                focused = false
            }
            busy = false
        }
    }
}

/// B8: the doodle full screen, who drew it and when, React, Edit and Draw new.
struct BoardViewer: View {
    let board: Board
    let home: Home
    let actions: HomeActions
    let canReact: Bool
    let onReact: () -> Void
    let onClose: () -> Void
    let onDraw: (String) -> Void

    @Environment(\.dlFirstCitizen) private var first

    var body: some View {
        let friend = home.friendName
        let mark = BoardReaction.of(board.reaction)
        let name = board.authorId == home.me.id ? "You" : friend
        ZStack {
            Color.dlLightbox.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.dlOnLightbox)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        BoardFrame { BoardImage(url: board.url) }
                            .accessibilityElement()
                            .accessibilityLabel("\(name == "You" ? "Your" : "\(name)’s") doodle")
                        if let mark {
                            HandReaction(reaction: mark, size: 84, tilt: 8, label: "\(canReact ? "Your reaction" : "\(friend) reacted"): \(mark.name)")
                                .padding(14)
                        }
                    }
                    BoardNote(board: board, home: home, actions: actions, viewer: true)
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    WhoDot(color: Who.of(board.authorId, first: first).signature)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).dlText(.subheadlineBold).foregroundStyle(.dlOnLightbox)
                        Text(DLTime.clock(board.createdAt)).dlText(.footnote).foregroundStyle(.dlOnLightboxQuiet)
                    }
                    Spacer(minLength: 0)
                    if canReact {
                        Button(action: onReact) {
                            Group {
                                if let mark { HandReaction(reaction: mark, size: 28) } else { ReactSlot(color: .dlOnLightbox, plus: .dlOnLightbox, size: 32) }
                            }
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mark.map { "Your reaction: \($0.name). Change it" } ?? "React")
                    }
                    viewerButton("pencil", "Edit", outlined: true) { onDraw("edit") }
                    viewerButton("scribble", "Draw new", outlined: false) { onDraw("new") }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func viewerButton(_ symbol: String, _ title: String, outlined: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.custom(DLFontName.manropeExtraBold.rawValue, size: 14, relativeTo: .subheadline))
            }
            .foregroundStyle(outlined ? Color.dlOnLightbox : Color.dlLightbox)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(outlined ? Color.clear : Color.dlOnLightbox, in: Capsule())
            .overlay(Capsule().strokeBorder(outlined ? Color.dlOnLightbox : .clear, lineWidth: 1))
        }
        .buttonStyle(DLPressStyle())
    }
}

/// Lays its child out at a fraction of the offered width (capped), from the leading edge.
private struct FractionWidth: Layout {
    let fraction: CGFloat
    let maxWidth: CGFloat
    let leading: CGFloat

    private func childWidth(_ width: CGFloat) -> CGFloat { min(width * fraction, maxWidth) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 370
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: childWidth(width), height: nil))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.minX + leading, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: childWidth(bounds.width), height: nil)
        )
    }
}
