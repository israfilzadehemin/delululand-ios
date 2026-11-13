import DLDesignSystem
import DLI18n
import DLUI
import SwiftUI

/*
 * Board reactions (web board/reactions.tsx, doc "Delululand — Board" §R): ten marker-drawn marks in
 * the board's ink colours on a 100-unit grid. A new mark draws itself in, stroke by stroke (R5).
 */

enum Ink {
    static let ink = Color(red: 0x33 / 255, green: 0x32 / 255, blue: 0x3B / 255)
    static let red = Color(red: 0xB2 / 255, green: 0x3A / 255, blue: 0x3A / 255)
    static let mustard = Color(red: 0xD4 / 255, green: 0xA2 / 255, blue: 0x4C / 255)
    static let sky = Color(red: 0x5B / 255, green: 0x8F / 255, blue: 0xC7 / 255)
    static let terracotta = Color(red: 0xC9 / 255, green: 0x6F / 255, blue: 0x52 / 255)
    static let lavender = Color(red: 0x8A / 255, green: 0x7B / 255, blue: 0xC0 / 255)
    static let navy = Color(red: 0x20 / 255, green: 0x2B / 255, blue: 0x45 / 255)
    static let slate = Color(red: 0x48 / 255, green: 0x53 / 255, blue: 0x6C / 255)
}

private let face = "M50 13 C73 12 88 30 87 51 C86 72 70 87 49 86 C27 86 13 70 14 49 C15 28 30 14 50 13"

struct Mark: Sendable {
    let d: String
    let color: Color
    let width: CGFloat
    var dot = false
}

private func s(_ d: String, _ c: Color, _ w: CGFloat) -> Mark { Mark(d: d, color: c, width: w) }

private func dot(_ x: CGFloat, _ y: CGFloat) -> Mark {
    Mark(d: "M\(x - 3.5) \(y) a3.5 3.5 0 1 0 7 0 a3.5 3.5 0 1 0 -7 0", color: Ink.ink, width: 3, dot: true)
}

struct BoardReaction: Identifiable, Sendable {
    let key: String
    /// The catalogue key of the name, read when shown so a language switch renames it.
    let nameKey: String
    let marks: [Mark]
    var name: String { t(nameKey) }
    var id: String { key }

    static func of(_ key: String?) -> BoardReaction? { all.first { $0.key == key } }

    static let all: [BoardReaction] = [
        BoardReaction(key: "love", nameKey: "board.reaction.love", marks: [
            s("M50 82 C22 63 12 46 19 31 C26 17 43 19 50 34 C57 19 74 16 81 30 C89 45 79 63 50 82 Z", Ink.red, 6),
            s("M29 33 q5 -8 13 -5", Ink.red, 3.5),
        ]),
        BoardReaction(key: "haha", nameKey: "board.reaction.haha", marks: [
            s(face, Ink.mustard, 6),
            s("M31 41 q6 -8 13 0 M56 41 q6 -8 13 0", Ink.ink, 5),
            s("M31 55 Q50 82 69 55 Z", Ink.ink, 5),
            s("M20 46 q-6 8 -2 13 M80 46 q6 8 2 13", Ink.sky, 4),
        ]),
        BoardReaction(key: "wow", nameKey: "board.reaction.wow", marks: [
            s(face, Ink.mustard, 6), dot(37, 40), dot(63, 40),
            s("M50 56 C58 56 59 72 50 72 C41 72 42 56 50 56", Ink.ink, 5),
            s("M30 28 q6 -5 12 -3 M58 25 q6 -2 12 3", Ink.ink, 3.5),
        ]),
        BoardReaction(key: "star", nameKey: "board.reaction.star", marks: [
            s("M50 11 L60 38 L89 39 L66 56 L75 85 L50 68 L26 85 L34 56 L11 39 L40 37 Z", Ink.mustard, 6),
            s("M82 14 v10 M77 19 h10", Ink.mustard, 3.5),
        ]),
        BoardReaction(key: "fire", nameKey: "board.reaction.fire", marks: [
            s("M50 89 C27 89 19 70 26 54 C31 44 39 39 37 24 C49 31 55 42 53 54 C59 48 61 39 59 30 C73 41 82 58 75 73 C71 83 62 89 50 89 Z", Ink.terracotta, 6),
            s("M50 83 C41 83 39 74 43 68 C47 62 48 58 47 52 C55 58 60 66 58 74 C56 80 54 83 50 83", Ink.mustard, 4.5),
        ]),
        BoardReaction(key: "yes", nameKey: "board.reaction.yes", marks: [
            s("M22 48 H38 V86 H22 Z", Ink.ink, 5.5),
            s("M38 51 L52 29 C55 20 66 22 64 33 L61 45 H79 C86 45 88 53 83 57 C88 61 86 67 81 69 C84 73 82 79 77 80 C78 86 73 88 69 88 H38", Ink.ink, 5.5),
        ]),
        BoardReaction(key: "aww", nameKey: "board.reaction.aww", marks: [
            s(face, Ink.sky, 6), dot(37, 42), dot(63, 42),
            s("M35 70 q15 -13 30 0", Ink.ink, 5),
            s("M66 50 c-5 8 -4 14 0 14 c4 0 5 -6 0 -14", Ink.sky, 3.5),
        ]),
        BoardReaction(key: "kiss", nameKey: "board.reaction.kiss", marks: [
            s("M14 50 C28 34 41 37 50 44 C59 37 72 34 86 50 C73 67 61 73 50 73 C39 73 27 67 14 50 Z", Ink.red, 6),
            s("M16 50 C36 55 64 55 84 50", Ink.red, 4),
            s("M74 16 c-3 -6 -11 -3 -8 3 l8 9 l8 -9 c3 -6 -5 -9 -8 -3", Ink.red, 3),
        ]),
        BoardReaction(key: "sparkle", nameKey: "board.reaction.sparkle", marks: [
            s("M40 18 C42 37 46 41 65 43 C46 45 42 49 40 68 C38 49 34 45 15 43 C34 41 38 37 40 18 Z", Ink.lavender, 5.5),
            s("M72 56 C73 65 75 67 84 68 C75 69 73 71 72 80 C71 71 69 69 60 68 C69 67 71 65 72 56 Z", Ink.mustard, 4.5),
            s("M74 14 v14 M67 21 h14", Ink.mustard, 4),
        ]),
        BoardReaction(key: "hundred", nameKey: "board.reaction.hundred", marks: [
            s("M14 36 L23 29 V70", Ink.red, 6),
            s("M45 30 C34 30 33 70 45 70 C57 70 56 30 45 30", Ink.red, 6),
            s("M73 30 C62 30 61 70 73 70 C85 70 84 30 73 30", Ink.red, 6),
            s("M12 80 Q50 74 89 80 M17 89 Q50 84 85 88", Ink.red, 4),
        ]),
    ]
}

/// One mark. `draw` plays the stroke-by-stroke draw-in (R5).
struct HandReaction: View {
    let reaction: BoardReaction
    let size: CGFloat
    var tilt: Double = 0
    var draw = false
    var label: String?

    @Environment(\.dlMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    var body: some View {
        let k = size / 100
        ZStack {
            ForEach(Array(reaction.marks.enumerated()), id: \.offset) { i, mark in
                let count = CGFloat(reaction.marks.count)
                let local = min(1, max(0, progress * count - CGFloat(i)))
                if mark.dot {
                    GridShape(mark.d).fill(mark.color).opacity(local >= 1 ? 1 : 0)
                    GridShape(mark.d).trim(from: 0, to: local).stroke(mark.color, lineWidth: mark.width * k)
                } else {
                    GridShape(mark.d)
                        .trim(from: 0, to: local)
                        .stroke(mark.color, style: StrokeStyle(lineWidth: mark.width * k, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt))
        .accessibilityElement()
        .accessibilityLabel(label ?? reaction.name)
        .onAppear { start() }
        .onChange(of: draw) { _, _ in start() }
        .onChange(of: reaction.key) { _, _ in start() }
    }

    private func start() {
        guard draw, motionEnabled, !reduceMotion else {
            progress = 1
            return
        }
        progress = 0
        withAnimation(.easeInOut(duration: 0.7)) { progress = 1 }
    }
}

/// The empty slot on the friend's doodle: a dashed smiley with a plus.
struct ReactSlot: View {
    var color = Ink.slate.opacity(0.55)
    var plus = Ink.navy
    var size: CGFloat = 44

    var body: some View {
        let k = size / 100
        ZStack {
            GridShape("M50 8 C74 7 92 27 91 51 C90 75 72 92 49 91 C25 91 8 73 9 49 C10 26 27 9 50 8")
                .stroke(color, style: StrokeStyle(lineWidth: 4 * k, lineCap: .round, dash: [9 * k, 9 * k]))
            GridShape("M36 42 v2 M62 42 v2").stroke(color, style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
            GridShape("M35 60 q15 12 30 0").stroke(color, style: StrokeStyle(lineWidth: 4.5 * k, lineCap: .round))
            GridShape("M80 14 v18 M71 23 h18").stroke(plus, style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// The marker ring around the chosen mark in the picker.
struct ChosenRing: View {
    var color: Color = .dlInk

    var body: some View {
        GeometryReader { geo in
            GridShape("M52 6 C78 6 95 26 93 52 C91 78 70 95 46 93 C22 91 6 72 8 48 C10 24 30 7 58 9")
                .stroke(color, style: StrokeStyle(lineWidth: 4 * geo.size.width / 100, lineCap: .round))
        }
    }
}
