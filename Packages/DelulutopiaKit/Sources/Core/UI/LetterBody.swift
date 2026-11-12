import DLDesignSystem
import DLNetwork
import SwiftUI
import UIKit

/// The whole letter takes at most this long to write itself onto the page (web text/LetterBody.tsx).
private let revealSeconds = 2.6
private let stepMax = 0.045

/// The one renderer for letter JSON (Technical Design §6.4): paragraphs, bullet lists, bold, italic,
/// underline, in Literata on the letter's line height. An empty paragraph keeps a short gap. `reveal`
/// writes the letter onto the page word by word: every word is laid out from the start, only its ink
/// fades in.
public struct LetterBody: View {
    let doc: Doc
    let size: CGFloat
    let lineHeight: CGFloat
    let color: Color
    let reveal: Bool

    @Environment(\.dlMotionEnabled) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started: Date?

    public init(_ doc: Doc, size: CGFloat = 17, lineHeight: CGFloat = 28, color: Color = .dlLetterInk, reveal: Bool = false) {
        self.doc = doc
        self.size = size
        self.lineHeight = lineHeight
        self.color = color
        self.reveal = reveal
    }

    private var animating: Bool { reveal && motion && !reduceMotion }

    public var body: some View {
        let words = Self.countWords(doc)
        let step = min(stepMax, revealSeconds / Double(max(1, words)))
        TimelineView(.animation(paused: !animating || started == nil)) { context in
            let elapsed = started.map { context.date.timeIntervalSince($0) } ?? 0
            let shown = animating ? elapsed / step : Double(words) + 1
            content(shown: shown)
        }
        .onAppear { if animating, started == nil { started = Date() } }
        .onChange(of: reveal) { _, on in started = on ? Date() : nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(doc.plainText)
    }

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// Each block with the index of its first word, so ink can be counted across the letter.
    private var starts: [Int] {
        var out: [Int] = []
        var i = 0
        func words(_ r: [TextRun]) -> Int { r.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
        for block in doc.content {
            out.append(i)
            switch block {
            case let .paragraph(r): i += words(r)
            case let .bulletList(items): i += items.reduce(0) { $0 + words($1) }
            }
        }
        return out
    }

    private func content(shown: Double) -> some View {
        let fontSize = size * scale
        let natural = UIFont(name: DLFontName.literataRegular.name, size: fontSize)?.lineHeight ?? fontSize * 1.3
        let spacing = max(0, lineHeight * scale - natural)
        let starts = starts
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(doc.content.enumerated()), id: \.offset) { b, block in
                switch block {
                case let .paragraph(runs):
                    if runs.allSatisfy({ $0.text.isEmpty }) {
                        Spacer().frame(height: lineHeight * scale * 0.45)
                    } else {
                        Text(Self.attributed(runs, start: starts[b], shown: shown, color: color, size: fontSize).0)
                            .lineSpacing(spacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .bulletList(items):
                    let itemStarts = items.indices.map { k in
                        starts[b] + items[..<k].reduce(0) { $0 + $1.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { k, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("•").font(.custom(DLFontName.literataRegular.name, fixedSize: fontSize)).foregroundStyle(color)
                                    .padding(.leading, 6)
                                Text(Self.attributed(item, start: itemStarts[k], shown: shown, color: color, size: fontSize).0)
                                    .lineSpacing(spacing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func countWords(_ doc: Doc) -> Int {
        func runs(_ r: [TextRun]) -> Int { r.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
        return doc.content.reduce(0) { total, block in
            switch block {
            case let .paragraph(r): total + runs(r)
            case let .bulletList(items): total + items.reduce(0) { $0 + runs($1) }
            }
        }
    }

    /// Styled runs; words past `shown` (a word index) are transparent ink. Returns its word count.
    static func attributed(_ runs: [TextRun], start: Int, shown: Double, color: Color, size: CGFloat) -> (AttributedString, Int) {
        var out = AttributedString()
        var i = start
        for run in runs {
            let face: DLFontName = switch (run.bold, run.italic) {
            case (true, true): .literataBoldItalic
            case (true, false): .literataBold
            case (false, true): .literataItalic
            case (false, false): .literataRegular
            }
            var pieces: [(String, Bool)] = []
            var current = ""
            var inSpace: Bool?
            for c in run.text {
                let space = c.isWhitespace
                if inSpace != nil, inSpace != space {
                    pieces.append((current, inSpace!))
                    current = ""
                }
                current.append(c)
                inSpace = space
            }
            if !current.isEmpty, let inSpace { pieces.append((current, inSpace)) }
            for (piece, space) in pieces {
                var a = AttributedString(piece)
                a.font = .custom(face.name, fixedSize: size)
                if run.underline { a.underlineStyle = .single }
                if space {
                    a.foregroundColor = color
                } else {
                    let alpha = min(1, max(0, shown - Double(i)))
                    i += 1
                    a.foregroundColor = color.opacity(alpha)
                }
                out += a
            }
        }
        return (out, i - start)
    }
}
