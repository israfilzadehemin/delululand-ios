import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import SwiftUI

/*
 * Discussions are sticky notes (Materials story; web styles/materials.css): a square note in the
 * colour its author picked, a sheen down to its foot, a red barrel pin pushed in at the top.
 */

public extension DLNoteColor {
    /// The API's colour (`lemon` … `mint`), lemon when unset.
    static func of(_ wire: String?) -> DLNoteColor {
        DLNoteColor.allCases.first { $0.rawValue == wire?.lowercased() && $0 != .blank } ?? .lemon
    }

    /// The six colours an author picks, in order.
    static let pickable: [DLNoteColor] = [.lemon, .peach, .pink, .lavender, .sky, .mint]
}

/// Ink on a note (contrast-checked in both themes).
public extension ShapeStyle where Self == Color {
    static var dlNoteInk: Color { DLColorToken(0x33323B, 0xECE4D6).color }
    static var dlNoteInkQuiet: Color { DLColorToken(0x424A5C, 0xC4B9A8).color }
}

/// A note's paper; `unseen` rings it in terracotta, `selected` in the seal.
public struct Note<Content: View>: View {
    let color: DLNoteColor
    let unseen: Bool
    let selected: Bool
    let pin: CGFloat
    let tilt: Double
    let content: Content

    public init(_ color: DLNoteColor, unseen: Bool = false, selected: Bool = false, pin: CGFloat = 20, tilt: Double = 0, @ViewBuilder content: () -> Content) {
        self.color = color
        self.unseen = unseen
        self.selected = selected
        self.pin = pin
        self.tilt = tilt
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(stops: [.init(color: color.face.color, location: 0.62), .init(color: color.deep.color, location: 1)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 2)
            )
            .overlay {
                if unseen || selected {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(selected ? Color.dlSeal : Color.dlMarkLine, lineWidth: selected ? 2 : 1.5)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 0.5, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 4, y: 3)
            .overlay(alignment: .top) {
                if pin > 0 { NotePin(width: pin).offset(y: -pin * 0.85) }
            }
            .opacity(color == .blank ? 0.88 : 1)
            .rotationEffect(.degrees(tilt))
    }
}

/// The red barrel map pin, leaning 28° about its point.
public struct NotePin: View {
    let width: CGFloat

    public init(width: CGFloat = 20) {
        self.width = width
    }

    public var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 40)
            let steel = Gradient(colors: [Color(red: 0.25, green: 0.26, blue: 0.29), Color(red: 0.84, green: 0.85, blue: 0.87), Color(red: 0.29, green: 0.31, blue: 0.33)])
            context.fill(PathData.path("M10.6 27.5 L13.4 27.5 L12.8 38.2 L12 39.8 L11.2 38.2 Z"),
                         with: .linearGradient(steel, startPoint: CGPoint(x: 10.6, y: 0), endPoint: CGPoint(x: 13.4, y: 0)))
            let barrel = Gradient(stops: [
                .init(color: Color(red: 0.43, green: 0.06, blue: 0.08), location: 0),
                .init(color: Color(red: 0.83, green: 0.23, blue: 0.22), location: 0.22),
                .init(color: Color(red: 0.95, green: 0.48, blue: 0.43), location: 0.38),
                .init(color: Color(red: 0.78, green: 0.16, blue: 0.17), location: 0.55),
                .init(color: Color(red: 0.42, green: 0.05, blue: 0.07), location: 1),
            ])
            let shade = GraphicsContext.Shading.linearGradient(barrel, startPoint: CGPoint(x: 4, y: 0), endPoint: CGPoint(x: 20, y: 0))
            context.fill(PathData.path("M3.6 27.6 C3.6 25.6 7.6 24.6 9 22.6 L15 22.6 C16.4 24.6 20.4 25.6 20.4 27.6 C20.4 29.4 3.6 29.4 3.6 27.6 Z"), with: shade)
            context.fill(PathData.path("M7.2 9.4 C8.8 12.6 9.2 18.6 8.6 23 C10.8 24.1 13.2 24.1 15.4 23 C14.8 18.6 15.2 12.6 16.8 9.4 Z"), with: shade)
            context.fill(PathData.path("M4.6 9.2 L4.6 6.6 C4.6 3 19.4 3 19.4 6.6 L19.4 9.2 C19.4 11 4.6 11 4.6 9.2 Z"), with: shade)
        }
        .frame(width: width, height: width * 5 / 3)
        .rotationEffect(.degrees(28), anchor: .bottom)
        .shadow(color: .black.opacity(0.25), radius: 1, x: 1, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Reaction notices (doc "Delululand — Replies & Reaction Notices")

private func clip(_ text: String, _ max: Int) -> String {
    text.count <= max ? text : String(text.prefix(max - 1)) + "…"
}

/// "Leyla reacted to 'see you at…' with 😂 · +2 more".
public func noticeLine(_ n: ReactionNotice, count: Int, reactorName: String) -> String {
    let more = count > 1 ? t("reactions.notice.more", ["n": count - 1]) : ""
    let line = if let text = n.text {
        t("reactions.notice.text", ["name": reactorName, "text": clip(text, 24), "emoji": n.emoji])
    } else {
        t(n.onMine ? "reactions.notice.mine" : "reactions.notice.theirs", ["name": reactorName, "item": itemWord(n), "emoji": n.emoji])
    }
    return line + more
}

private func itemWord(_ n: ReactionNotice) -> String {
    if n.target == "discussion" { return t("reactions.item.discussion") }
    if n.target == "comment" { return t("reactions.item.comment") }
    switch n.media {
    case "video": return t("reactions.item.video")
    case "photo": return t("reactions.item.photo")
    case "audio": return t("reactions.item.voiceNote")
    default: return t("reactions.item.email")
    }
}

/// An unseen reaction is the row's line while it is the newest activity.
public func reactionWins(_ n: ReactionNotice?, count: Int, otherActivityAt: String?) -> Bool {
    guard let n, count > 0 else { return false }
    guard let other = DLTime.date(otherActivityAt) else { return true }
    return (DLTime.date(n.at) ?? .distantPast) > other
}

/// A reaction row (web Reactions.tsx): one chip per emoji (mine marked), then the face-plus that
/// opens the picker: the eight recent emojis and "every emoji".
public struct ReactionRow: View {
    let reactions: [Reaction]
    let me: Int
    let compact: Bool
    let enabled: Bool
    let onToggle: (String) -> Void

    @Environment(Backend.self) private var backend
    @State private var picking = false
    @State private var every = false
    @State private var picked = ""

    public init(_ reactions: [Reaction], me: Int, compact: Bool = false, enabled: Bool = true, onToggle: @escaping (String) -> Void) {
        self.reactions = reactions
        self.me = me
        self.compact = compact
        self.enabled = enabled
        self.onToggle = onToggle
    }

    public static let quick = ["❤️", "😂", "😮", "😢", "👍", "🙏", "🔥", "🥰"]

    public var body: some View {
        FlowRow(spacing: 6) {
            ForEach(reactions) { r in
                DLReactionChip(r.emoji, count: r.userIds.count, mine: r.userIds.contains(me), compact: compact) { onToggle(r.emoji) }
                    .disabled(!enabled)
            }
            if enabled {
                DLAddReactionButton(compact: compact) { picking = true }
                    .popover(isPresented: $picking, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        picker.presentationCompactAdaptation(.popover)
                    }
            }
        }
        .onChange(of: picked) { _, emoji in
            guard !emoji.isEmpty else { return }
            remember(emoji)
            onToggle(emoji)
            picked = ""
            picking = false
        }
    }

    private var recent: [String] {
        let saved = backend.settings.recentEmojis
        var out = saved
        for e in Self.quick where !out.contains(e) { out.append(e) }
        return Array(out.prefix(8))
    }

    private func remember(_ emoji: String) {
        backend.settings.pushRecentEmoji(emoji)
    }

    private var picker: some View {
        HStack(spacing: 2) {
            ForEach(recent, id: \.self) { e in
                Button {
                    picking = false
                    remember(e)
                    onToggle(e)
                } label: {
                    Text(e).font(.system(size: 26)).frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
            }
            EmojiInput(emoji: $picked, isEditing: $every) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 20))
                    .foregroundStyle(.dlInkQuiet)
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(t("reactions.allEmojis"))
        }
        .padding(.horizontal, 6)
    }
}

/// Wraps its children onto as many lines as they need.
public struct FlowRow: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
