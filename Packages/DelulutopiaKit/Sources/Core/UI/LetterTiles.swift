import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import SwiftUI

/*
 * The materials letters are made of (web components/Materials.tsx, styles/materials.css; canvas
 * A-Home, C-Letters): slim envelopes with a flap and the writer's wax seal, unfolded sheets with a
 * margin line and a dog-eared corner. Purely visual.
 */

public enum TileShape: Sendable { case envelope, sheet }

/// What a row says when there is no text (FS-R12).
public func firstLineOf(_ firstLine: String?, media: LetterMedia?) -> String {
    if let firstLine, !firstLine.isEmpty { return firstLine }
    guard let media else { return "" }
    if media.photos > 0 { return t("emails.media.photo") }
    if media.audios > 0 { return t("emails.media.voiceNote") }
    if media.doodles > 0 { return t("media.doodle") }
    return ""
}

public func firstLineOf(_ row: LetterRow) -> String { firstLineOf(row.firstLine, media: row.media) }

/// A sealed envelope until the letter has arrived and been opened, an unfolded sheet after. A sent
/// letter that has arrived but is unread is a sheet.
public func tileShapeOf(_ row: LetterRow, state: String) -> TileShape {
    let arrived = state == LetterState.delivered || state == LetterState.read
    if !arrived { return .envelope }
    return row.direction == "from" && state == LetterState.delivered ? .envelope : .sheet
}

/// Each stamp sits a little askew, the same way every time for the same letter.
public func stampTilt(_ id: Int) -> Double {
    [4, -3, 3, -2, 2, -4][abs(id) % 6]
}

/// A letter row on Home or in the list. `reach` is the in-reach tint (it can still be edited or
/// cancelled).
public struct LetterTile<Content: View>: View {
    let shape: TileShape
    let who: Who
    let reach: Bool
    let content: Content

    public init(_ shape: TileShape, who: Who, reach: Bool = false, @ViewBuilder content: () -> Content) {
        self.shape = shape
        self.who = who
        self.reach = reach
        self.content = content()
    }

    private var fill: Color {
        if reach { return .dlMarkContainer }
        return shape == .envelope ? .dlLetterEnvelope : .dlLetterSheet
    }

    public var body: some View {
        let corner = RoundedRectangle(cornerRadius: 4)
        Group {
            if shape == .envelope {
                VStack(alignment: .leading, spacing: 8) { content }
                    .padding(EdgeInsets(top: 30, leading: 14, bottom: 12, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .top) { Flap(seal: who.signature) }
            } else {
                VStack(alignment: .leading, spacing: 8) { content }
                    .padding(EdgeInsets(top: 12, leading: 18, bottom: 14, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .leading) {
                        Rectangle().fill(.dlLetterMargin).frame(width: 1).padding(.leading, 7)
                    }
                    .overlay(on: .bottomRight) { DogEar() }
            }
        }
        .background(fill, in: corner)
        .clipShape(corner)
        .overlay(corner.strokeBorder(reach ? Color.dlMarkLine : Color.dlLetterInk.opacity(0.22), lineWidth: reach ? 1 : 0.5))
        .shadow(color: .dlShade.opacity(0.12), radius: 1.5, y: 1)
        .contentShape(corner)
    }
}

/// The flap across the top of an envelope row, and its seal.
private struct Flap: View {
    let seal: Color

    var body: some View {
        ZStack(alignment: .top) {
            FlapShape().fill(.dlLetterFlap)
            FlapShape().stroke(.dlLetterEdge, lineWidth: 1)
            WaxSeal(color: seal).offset(y: 11)
        }
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct FlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height * 20 / 22))
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.closeSubpath()
        return p
    }
}

/// A small wax seal in the writer's colour.
public struct WaxSeal: View {
    let color: Color
    let size: CGFloat

    public init(color: Color, size: CGFloat = 16) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Ellipse()
            .fill(color)
            .overlay(Ellipse().strokeBorder(.white.opacity(0.2), lineWidth: 2))
            .overlay(
                Ellipse()
                    .fill(LinearGradient(colors: [.clear, .black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .blendMode(.multiply)
            )
            .frame(width: size, height: size * 0.97)
            .shadow(color: .dlShade.opacity(0.3), radius: 1, y: 1)
    }
}

/// The dog-eared corner of a sheet: the page's ground where the corner folded away, the flap colour
/// its back.
public struct DogEar: View {
    let ground: Color

    public init(ground: Color = .dlPaper) {
        self.ground = ground
    }

    public var body: some View {
        ZStack {
            Triangle(corner: .bottomTrailing).fill(ground)
            Triangle(corner: .topLeading).fill(.dlLetterFlap)
                .shadow(color: .dlShade.opacity(0.12), radius: 1, x: -1, y: -1)
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    private struct Triangle: Shape {
        enum Corner { case topLeading, bottomTrailing }
        let corner: Corner

        func path(in rect: CGRect) -> Path {
            var p = Path()
            switch corner {
            case .topLeading:
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .bottomTrailing:
                p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            p.closeSubpath()
            return p
        }
    }
}

/// The incoming arc (UX S2): a dotted path, the travelled part in the writer's colour, a plane on it.
/// It glides each second so the plane moves continuously.
public struct LetterArc: View {
    let progress: Double
    let who: Who
    @Environment(\.dlMotionEnabled) private var motion

    public init(progress: Double, who: Who) {
        self.progress = min(1, max(0, progress))
        self.who = who
    }

    public var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * progress
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 7))
                    p.addLine(to: CGPoint(x: geo.size.width, y: 7))
                }
                .stroke(.dlLetterEdge, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 3.4]))
                Rectangle().fill(who.signature).frame(width: x, height: 1.5).offset(y: 6.25)
                ZStack {
                    GridShape("M3 11l18-8-7 18-3-7z", grid: 24).fill(.dlLetterEnvelope)
                    GridShape("M3 11l18-8-7 18-3-7z", grid: 24)
                        .stroke(.dlLetterInk, style: StrokeStyle(lineWidth: 2 * 14 / 24, lineJoin: .round))
                }
                .frame(width: 14, height: 14)
                .offset(x: x - 7)
            }
            .animation(motion ? .linear(duration: 1) : nil, value: progress)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// How far a letter has travelled, 0…1.
public func travelled(_ row: LetterRow, now: Date) -> Double {
    guard let start = DLTime.date(row.sentAt), let end = DLTime.date(row.arrivesAt), end > start else { return 1 }
    return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
}

/// Edit and Cancel in reach (web .dl-outline-btn): 40 pt, navy outline on the letter surface, 14/800.
public struct ReachButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(DLFontName.manropeExtraBold.name, size: 14, relativeTo: .subheadline))
                .foregroundStyle(.dlSeal)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.dlLetterEnvelope, in: Capsule())
                .overlay(Capsule().strokeBorder(.dlSeal, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(DLPressStyle())
    }
}

/// The NEW chip: terracotta on letters and notes, the navy seal on the board.
public struct NewChip: View {
    let paper: Bool
    let text: String

    public init(_ text: String = t("board.new"), paper: Bool = true) {
        self.text = text
        self.paper = paper
    }

    public var body: some View {
        Text(text)
            .font(.custom(DLFontName.manropeExtraBold.name, fixedSize: 11))
            .tracking(0.88)
            .foregroundStyle(paper ? Color.dlOnNewBadge : Color.white)
            .padding(.horizontal, paper ? 9 : 8)
            .frame(height: paper ? 22 : 20)
            .background(paper ? Color.dlNewBadge : Color.dlSeal, in: Capsule())
            .dlEnter(.pop, delay: 0.16)
    }
}

/// A stamp on a row's trailing edge, askew with a soft shadow.
public struct RowStamp: View {
    let stamp: StampMark
    let id: Int
    let width: CGFloat

    public init(_ stamp: StampMark, id: Int, width: CGFloat = 26) {
        self.stamp = stamp
        self.id = id
        self.width = width
    }

    public var body: some View {
        StampImage(url: stamp.imageUrl, name: stamp.name, width: width)
            .rotationEffect(.degrees(stampTilt(id)))
            .shadow(color: .dlShade.opacity(0.25), radius: 0.5, y: 1)
    }
}

/// "Take it back?" (FS-S5, C1): a confirmation dialog on the letter row or page.
public extension View {
    func takeBackDialog(
        isPresented: Binding<Bool>,
        friend: String,
        draftEmpty: Bool,
        onYes: @escaping () -> Void
    ) -> some View {
        confirmationDialog(t("discussions.takeItBack"), isPresented: isPresented, titleVisibility: .visible) {
            Button(t("discussions.yesTakeItBack"), role: .destructive, action: onYes)
            Button(t("discussions.no"), role: .cancel) {}
        } message: {
            Text(t("letters.theLetterLeavesSHome", ["friend": friend])
                + (draftEmpty ? "" : " " + t("letters.thisReplacesYourCurrentDraft")))
        }
    }
}

/// The copy of a cancel that failed, and the cancel itself (from Home or a letter page).
public enum LetterActions {
    public static var tooLate: String { t("common.tooLate") }
    public static var notCancelled: String { t("letters.notCancelled") }

    public enum CancelResult: Sendable { case done, tooLate, failed }

    @MainActor
    public static func cancel(_ id: Int, backend: Backend) async -> CancelResult {
        do {
            _ = try await backend.api.cancelLetter(id: id)
            await backend.home.load()
            return .done
        } catch let error as APIError {
            backend.home.refreshSoon()
            return error.code == "WINDOW_CLOSED" ? .tooLate : .failed
        } catch {
            backend.home.refreshSoon()
            return .failed
        }
    }
}

/// The bar above a sent letter or discussion still in reach (web .dl-reach-bar): the seal tint with
/// its line, 12 pt corners, the count 13/600 and the actions at the end. Drops in.
public struct ReachBar<Actions: View>: View {
    let text: String
    let actions: Actions

    public init(_ text: String, @ViewBuilder actions: () -> Actions) {
        self.text = text
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.custom(DLFontName.manropeSemiBold.name, size: 13, relativeTo: .footnote).monospacedDigit())
                .foregroundStyle(.dlInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.dlSealTint, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.dlSealTintLine))
        .dlEnter(.drop)
    }
}

/// A compact reach button for bars (padded, not stretched).
public struct ReachChip: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(DLFontName.manropeExtraBold.name, size: 14, relativeTo: .subheadline))
                .foregroundStyle(.dlSeal)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(.dlLetterEnvelope, in: Capsule())
                .overlay(Capsule().strokeBorder(.dlSeal, lineWidth: 1.5))
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(DLPressStyle())
    }
}
