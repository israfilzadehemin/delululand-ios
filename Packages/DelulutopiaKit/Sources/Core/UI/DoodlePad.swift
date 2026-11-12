import DLData
import DLDesignSystem
import DLNetwork
import SwiftUI
import UIKit

/*
 * Doodles (web doodle/doodle.ts, doc "Delululand — Doodles"): a list of actions (strokes and
 * clears); undo and redo move actions between two stacks; what the pad shows and exports is the
 * strokes after the last clear, drawn in order on the paper (D4).
 */

/// What a pad draws on: its stored size in pixels and the paper baked under the ink.
public struct DoodleSurface: Sendable, Equatable {
    public let width: CGFloat
    public let height: CGFloat
    public let paper: UInt32

    /// D3, D4: a 1024 px square of paper, so a doodle looks the same in both themes.
    public static let letter = DoodleSurface(width: 1024, height: 1024, paper: 0xF5F0E8)
    /// Board B5, B6: 1024 × 768 (4:3) on the whiteboard.
    public static let board = DoodleSurface(width: 1024, height: 768, paper: 0xFBFBF8)

    var paperColor: UIColor { UIColor(rgb: paper) }
}

/// Q4 Standard: 8 palette colours (the ink baked into the PNG, the same on every client).
public let doodleColours: [(name: String, rgb: UInt32)] = [
    ("Ink", 0x33323B), ("Navy", 0x202B45), ("Terracotta", 0xC96F52), ("Red", 0xB23A3A),
    ("Mustard", 0xD4A24C), ("Sage", 0x5F8A7D), ("Sky", 0x5B8FC7), ("Lavender", 0x8A7BC0),
]

/// Q4 Standard: 3 brush sizes in canvas pixels; the eraser is 2.5 × wider.
public let doodleSizes: [(name: String, width: CGFloat, dot: CGFloat)] = [("Fine", 6, 5), ("Medium", 14, 9), ("Bold", 32, 14)]
private let eraserFactor: CGFloat = 2.5
private let minStep: CGFloat = 1.5

public struct DoodleStroke: Sendable {
    public var rgb: UInt32
    public var width: CGFloat
    public var erase: Bool
    public var points: [CGPoint] = []

    mutating func extend(_ p: CGPoint) {
        if let last = points.last, hypot(p.x - last.x, p.y - last.y) < minStep { return }
        points.append(p)
    }
}

public struct DoodleHistory: Sendable {
    enum Action: Sendable { case draw(DoodleStroke), clear }

    var done: [Action] = []
    var undone: [Action] = []

    public init() {}

    /// The strokes on the pad now: everything after the last clear.
    public var visible: [DoodleStroke] {
        var out: [DoodleStroke] = []
        for action in done {
            switch action {
            case let .draw(s): out.append(s)
            case .clear: out.removeAll()
            }
        }
        return out
    }

    public var cleared: Bool { done.contains { if case .clear = $0 { true } else { false } } }
    /// D6: nothing drawn, or only eraser strokes.
    public var isBlank: Bool { !visible.contains { !$0.erase } }
    /// Board edit §E: over a backdrop the pad can post once anything changed it.
    public var isUnchanged: Bool { cleared ? isBlank : visible.isEmpty }
    public var canUndo: Bool { !done.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }
    public func canClear(backdrop: Bool) -> Bool { !visible.isEmpty || (backdrop && !cleared) }

    mutating func add(_ s: DoodleStroke) {
        done.append(.draw(s))
        undone.removeAll()
    }

    mutating func clear(backdrop: Bool) {
        guard canClear(backdrop: backdrop) else { return }
        done.append(.clear)
        undone.removeAll()
    }

    mutating func undo() {
        guard let last = done.popLast() else { return }
        undone.append(last)
    }

    mutating func redo() {
        guard let last = undone.popLast() else { return }
        done.append(last)
    }
}

enum DoodleRender {
    /// One stroke, smoothed through the midpoints of successive points; a tap is a dot. The eraser
    /// paints paper (the paper is part of the image, so erasing to it is exact).
    static func path(_ s: DoodleStroke) -> Path {
        var path = Path()
        let pts = s.points
        guard let first = pts.first else { return path }
        if pts.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - s.width / 2, y: first.y - s.width / 2, width: s.width, height: s.width))
            return path
        }
        path.move(to: first)
        for i in 1 ..< pts.count - 1 {
            let p = pts[i], q = pts[i + 1]
            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    static func draw(_ s: DoodleStroke, paper: UInt32, in context: inout GraphicsContext) {
        let color = Color(uiColor: UIColor(rgb: s.erase ? paper : s.rgb))
        let path = path(s)
        if s.points.count == 1 {
            context.fill(path, with: .color(color))
        } else {
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
        }
    }

    /// Paper, then the backdrop unless a clear wiped it, then every visible stroke, at `scale`.
    static func render(_ history: DoodleHistory, surface: DoodleSurface, backdrop: UIImage?, scale: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: 0, width: surface.width * scale, height: surface.height * scale)
        context.fill(Path(rect), with: .color(Color(uiColor: surface.paperColor)))
        if let backdrop, !history.cleared {
            context.draw(Image(uiImage: backdrop), in: rect)
        }
        context.scaleBy(x: scale, y: scale)
        for s in history.visible {
            draw(s, paper: surface.paper, in: &context)
        }
    }

    /// The PNG Done exports, at the surface's pixel size.
    @MainActor
    static func png(_ history: DoodleHistory, surface: DoodleSurface, backdrop: UIImage?) -> Data? {
        let view = Canvas { context, _ in
            render(history, surface: surface, backdrop: backdrop, scale: 1, in: &context)
        }
        .frame(width: surface.width, height: surface.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The whiteboard (web .dl-board): grey frame, the 4:3 surface, the tray with two markers.
public struct BoardFrame<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(.dlBoardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.dlInk.opacity(0.08)))
            .padding(EdgeInsets(top: 7, leading: 7, bottom: 15, trailing: 7))
            .background(alignment: .bottom) {
                ZStack(alignment: .bottomTrailing) {
                    Capsule().fill(.dlBoardTray).frame(height: 6).padding(.horizontal, 21).padding(.bottom, 4)
                    HStack(spacing: 6) {
                        Marker(color: Color(red: 0.788, green: 0.435, blue: 0.322))
                        Marker(color: Color(red: 0.125, green: 0.169, blue: 0.271))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 2)
                }
            }
            .background(.dlBoardFrame, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 8)
    }

    private struct Marker: View {
        let color: Color
        var body: some View {
            Capsule().fill(color).frame(width: 34, height: 6).shadow(color: .black.opacity(0.25), radius: 0.5, y: 1)
        }
    }
}

/// The doodle pad (canvas B-Pad): a full-screen page with Close, the title and its note, Post or
/// Done, the paper (or the whiteboard), and the glass tool panel: 8 colours, 3 sizes, eraser, undo,
/// redo and clear. Closing with ink on it asks first (I-2).
public struct DoodlePad: View {
    let surface: DoodleSurface
    let title: String
    let doneLabel: String
    let busyLabel: String?
    let busy: Bool
    let note: String?
    let backdropURL: String?
    let onDone: (Data) -> Void
    let onClose: () -> Void
    let onBackdropError: () -> Void

    @Environment(Backend.self) private var backend
    @State private var history = DoodleHistory()
    @State private var current: DoodleStroke?
    @State private var colour = doodleColours[0].rgb
    @State private var brush = 1
    @State private var eraser = false
    @State private var askDiscard = false
    @State private var backdrop: UIImage?

    public init(
        surface: DoodleSurface = .letter,
        title: String = "Doodle",
        doneLabel: String = "Done",
        busyLabel: String? = nil,
        busy: Bool = false,
        note: String? = nil,
        backdrop: String? = nil,
        onDone: @escaping (Data) -> Void,
        onClose: @escaping () -> Void,
        onBackdropError: @escaping () -> Void = {}
    ) {
        self.surface = surface
        self.title = title
        self.doneLabel = doneLabel
        self.busyLabel = busyLabel
        self.busy = busy
        self.note = note
        self.backdropURL = backdrop
        self.onDone = onDone
        self.onClose = onClose
        self.onBackdropError = onBackdropError
    }

    private var isBoard: Bool { surface == .board }
    private var waiting: Bool { backdropURL != nil && backdrop == nil }
    private var blank: Bool { backdropURL != nil ? history.isUnchanged : history.isBlank }

    public var body: some View {
        ZStack {
            Color.dlPaper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                paper
                    .padding(.horizontal, 10)
                Spacer(minLength: 12)
                tools
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .interactiveDismissDisabled(!history.isUnchanged)
        .confirmationDialog("Discard doodle?", isPresented: $askDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onClose)
            Button("Keep drawing", role: .cancel) {}
        }
        .task(id: backdropURL) {
            guard let backdropURL else { return }
            if let image = await ImageCache.shared.load(backdropURL, client: backend.client, maxPixel: 2048) {
                backdrop = image
            } else {
                onBackdropError()
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 17, relativeTo: .headline))
                    .tracking(-0.17)
                    .lineLimit(1)
                if let note {
                    Text(note)
                        .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 12, relativeTo: .caption))
                        .foregroundStyle(.dlInkQuiet)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.dlInk)
            .padding(.horizontal, 96)
            HStack {
                DLGlassIconButton("xmark", label: "Close") {
                    if history.isUnchanged { onClose() } else { askDiscard = true }
                }
                Spacer()
                Button {
                    guard let png = DoodleRender.png(history, surface: surface, backdrop: backdrop) else { return }
                    onDone(png)
                } label: {
                    Text(busy ? (busyLabel ?? doneLabel) : doneLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color.dlSeal.opacity(blank || busy || waiting ? 0.4 : 1), in: Capsule())
                        .shadow(color: .dlSeal.opacity(0.25), radius: 9, y: 6)
                }
                .disabled(blank || busy || waiting)
                .accessibilityLabel(doneLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var paper: some View {
        let label = backdropURL != nil ? "The doodle you are editing" : (blank ? (isBoard ? "Empty board" : "Empty drawing paper") : "Your doodle")
        let canvas = GeometryReader { geo in
            let scale = geo.size.width / surface.width
            Canvas { context, _ in
                var history = history
                if let current { history.done.append(.draw(current)) }
                DoodleRender.render(history, surface: surface, backdrop: backdrop, scale: scale, in: &context)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = CGPoint(
                            x: min(surface.width, max(0, value.location.x / scale)),
                            y: min(surface.height, max(0, value.location.y / scale))
                        )
                        if current == nil {
                            let width = doodleSizes[brush].width * (eraser ? eraserFactor : 1)
                            current = DoodleStroke(rgb: colour, width: width, erase: eraser)
                        }
                        current?.extend(p)
                    }
                    .onEnded { _ in
                        if let s = current { history.add(s) }
                        current = nil
                    }
            )
            .overlay {
                if waiting { ProgressView() }
            }
        }
        .aspectRatio(surface.width / surface.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.allowsDirectInteraction)

        if isBoard {
            BoardFrame { canvas }
        } else {
            canvas
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .dlShade.opacity(0.12), radius: 3, y: 1)
        }
    }

    private var tools: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(doodleColours, id: \.rgb) { c in
                    let on = colour == c.rgb && !eraser
                    Button {
                        colour = c.rgb
                        eraser = false
                    } label: {
                        Circle()
                            .fill(Color(uiColor: UIColor(rgb: c.rgb)))
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: on ? 0 : 1))
                            .frame(width: 32, height: 32)
                            .padding(on ? 2 : 0)
                            .background(on ? Circle().fill(.dlSheet) : nil)
                            .padding(on ? 2 : 0)
                            .background(on ? Circle().fill(.dlSeal) : nil)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    if c.rgb != doodleColours.last?.rgb { Spacer(minLength: 0) }
                }
            }
            HStack {
                HStack(spacing: 2) {
                    ForEach(doodleSizes.indices, id: \.self) { i in
                        let on = brush == i
                        Button { brush = i } label: {
                            Circle().fill(.dlInk).frame(width: doodleSizes[i].dot, height: doodleSizes[i].dot)
                                .frame(width: 40, height: 40)
                                .background(on ? Circle().fill(Color.dlSeal.opacity(0.09)) : nil)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(doodleSizes[i].name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Spacer()
                HStack(spacing: 2) {
                    tool("eraser", "Eraser", on: eraser) { eraser.toggle() }
                    tool("arrow.uturn.backward", "Undo", enabled: history.canUndo) { history.undo() }
                    tool("arrow.uturn.forward", "Redo", enabled: history.canRedo) { history.redo() }
                    tool("trash", "Clear", enabled: history.canClear(backdrop: backdropURL != nil)) { history.clear(backdrop: backdropURL != nil) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .dlGlass(in: RoundedRectangle(cornerRadius: 30))
    }

    private func tool(_ symbol: String, _ label: String, on: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(enabled ? Color.dlInk : Color.dlInkDisabled)
                .frame(width: 44, height: 44)
                .background(on ? Circle().fill(Color.dlSeal.opacity(0.09)) : nil)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
