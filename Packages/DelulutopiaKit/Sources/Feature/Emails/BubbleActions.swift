import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI
import UIKit

// Bubble actions (doc "Delululand — Bubble Actions" BA1–BA10; web emails/bubbleActions.tsx): the ↩ disc
// beside the bubble (BA2), the pill on its edge (BA7), the long-press layer (BA4, BA5) and the
// Reactions sheet behind the pill (BA8). The time inside the bubble (BA1) is drawn by the bubble.

/// Where a bubble is on screen, kept without redrawing the bubble each scroll frame (BA4).
final class FrameBox {
    var rect: CGRect = .zero
}

/// BA2: the ↩ disc on the bubble's free side: a 28 pt face in a 44 pt target.
struct ReplyDisc: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.dlInkQuiet)
                .flipsForRightToLeftLayoutDirection(true)
                .frame(width: 28, height: 28)
                .background(Color.dlPaperLetter.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(Color.dlLine, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(DLPressStyle(scale: 0.92))
        .accessibilityLabel(t("emails.reply"))
    }
}

/// BA7: one button over the bubble's bottom edge: up to three emojis and the total; highlighted
/// when mine is among them. A tap opens the Reactions sheet, a long press the layer.
struct ReactionPill: View {
    let reactions: [Reaction]
    let mine: Bool
    let onOpen: () -> Void
    let onLong: () -> Void

    var body: some View {
        let p = BubbleActionsSpec.pill(reactions)
        Button(action: onOpen) {
            HStack(spacing: 3) {
                Text(p.shown.joined()).font(.system(size: 14)).tracking(1)
                if p.total > 1 {
                    Text(formatNumber(p.total)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.dlInk)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(mine ? Color.dlSealTint : Color.dlPaperLetter, in: Capsule())
            .overlay(Capsule().strokeBorder(mine ? Color.dlSeal.opacity(0.5) : Color.dlLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A Button and a UIKit long-press: neither takes a scroll that starts on the pill.
        .holdToReact(onLong)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("emails.reactionsPill", ["list": reactions.map(\.emoji).joined(separator: " "), "n": formatNumber(p.total)]))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }
}

/// BA4: scrim, a lifted copy of the bubble moved only as far as needed to fit, the quick row (six
/// recents + ⋯) above it and Reply / Copy text below in a glass menu. A pick toggles mine and
/// closes; the scrim or the escape gesture closes it. `frame` is the bubble in screen points.
struct BubbleLayer<Copy: View>: View {
    let frame: CGRect
    let mine: Bool
    let quick: [String]
    let isMine: (String) -> Bool
    let canCopy: Bool
    /// Read Ticks TK6, TK7: the delivery card above the quick row, ``infoRows`` rows tall.
    let infoRows: Int
    let info: AnyView?
    let onPick: (String) -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void
    /// Stickers SK7: a sticker's ★ Add to / Remove from favourites; nil for other emails.
    let favourite: StickerFavourite?
    let copy: () -> Copy

    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var picked = ""
    @State private var every = false

    init(
        frame: CGRect,
        mine: Bool,
        quick: [String],
        isMine: @escaping (String) -> Bool,
        canCopy: Bool,
        infoRows: Int = 0,
        info: AnyView? = nil,
        onPick: @escaping (String) -> Void,
        onReply: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onClose: @escaping () -> Void,
        favourite: StickerFavourite? = nil,
        @ViewBuilder copy: @escaping () -> Copy
    ) {
        self.favourite = favourite
        self.frame = frame
        self.mine = mine
        self.quick = quick
        self.isMine = isMine
        self.canCopy = canCopy
        self.infoRows = infoRows
        self.info = info
        self.onPick = onPick
        self.onReply = onReply
        self.onCopy = onCopy
        self.onClose = onClose
        self.copy = copy
    }

    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let screenH = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            // Line up with the bubble's outer edge: the friend's start edge, my end edge.
            let left = mine == (direction == .rightToLeft)
            let above: CGFloat = 52 + 10 + (info == nil ? 0 : CGFloat(infoRows) * 28 + 12 + 2 + 8)
            let rows = 1 + (canCopy ? 1 : 0) + (favourite == nil ? 0 : 1)
            let below = CGFloat(rows * 48 + 14)
            let topEdge = geo.safeAreaInsets.top + 12
            let bottomEdge = screenH - geo.safeAreaInsets.bottom - 12
            let maxH = max(80, bottomEdge - topEdge - above - below)
            let h = min(frame.height, maxH)
            let top = min(max(frame.minY, topEdge + above), bottomEdge - below - h) - above
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.36)
                    .opacity(shown ? 1 : 0)
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                VStack(alignment: left == (direction == .leftToRight) ? .leading : .trailing, spacing: 0) {
                    if let info { info.padding(.bottom, 8).opacity(shown ? 1 : 0) }
                    quickRow.padding(.bottom, 10)
                    copy()
                        .frame(width: frame.width)
                        .frame(maxHeight: maxH, alignment: .top)
                        .clipped()
                        .scaleEffect(shown ? 1.02 : 1)
                        .shadow(color: .black.opacity(shown ? 0.22 : 0), radius: 17, y: 14)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    menu.padding(.top, 14)
                }
                .environment(\.layoutDirection, direction)
                .opacity(shown ? 1 : 0)
                .padding(.leading, left ? max(8, frame.minX) : 0)
                .padding(.trailing, left ? 0 : max(8, screenW - frame.maxX))
                .frame(width: screenW, alignment: left ? .leading : .trailing)
                .offset(y: top)
            }
            .environment(\.layoutDirection, .leftToRight)
            .ignoresSafeArea()
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.2)) { shown = true }
        }
        .onChange(of: picked) { _, emoji in
            guard !emoji.isEmpty else { return }
            picked = ""
            every = false
            if isMine(emoji) { onClose() } else { onPick(emoji) }
        }
    }

    private var quickRow: some View {
        HStack(spacing: 2) {
            ForEach(quick, id: \.self) { e in
                let on = isMine(e)
                Button { onPick(e) } label: {
                    Text(e)
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .background(on ? Color.dlSealTint : Color.clear, in: Circle())
                        .overlay(Circle().strokeBorder(on ? Color.dlSeal.opacity(0.5) : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            EmojiInput(emoji: $picked, isEditing: $every) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.dlInkQuiet)
                    .frame(width: 44, height: 44)
                    .background(Color.dlPaper, in: Circle())
            }
            .accessibilityLabel(t("reactions.allEmojis"))
            .accessibilityAddTraits(.isButton)
        }
        .padding(4)
        .background(Color.dlPaperLetter, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.dlLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .scaleEffect(shown || reduceMotion ? 1 : 0.85, anchor: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("emails.react"))
    }

    private var menu: some View {
        VStack(spacing: 0) {
            item(t("emails.reply"), systemImage: "arrowshape.turn.up.left", action: onReply)
            if canCopy {
                Divider()
                item(t("emails.copyText"), systemImage: "doc.on.doc", action: onCopy)
            }
            if let favourite {
                Divider()
                item(
                    favourite.on ? t("stickers.removeFavourite") : t("stickers.addFavourite"),
                    systemImage: favourite.on ? "star.fill" : "star",
                    action: favourite.toggle
                )
            }
        }
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.dlLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .offset(y: shown || reduceMotion ? 0 : 6)
    }

    private func item(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.dlInkQuiet)
                    .flipsForRightToLeftLayoutDirection(systemImage.hasPrefix("arrowshape"))
                    .frame(width: 20)
                Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(.dlInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// BA8: who reacted with each emoji. Mine can be removed, the friend's-only ones added; "Another
/// reaction" opens the emoji keyboard. Closes itself when the last one goes.
struct ReactionsSheet: View {
    let reactions: [Reaction]
    let meId: PublicID
    let nameOf: (PublicID) -> String
    let onToggle: (String, Bool) -> Void
    let onClose: () -> Void

    @State private var picked = ""
    @State private var every = false

    init(
        reactions: [Reaction],
        meId: PublicID,
        nameOf: @escaping (PublicID) -> String,
        onToggle: @escaping (String, Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.reactions = reactions
        self.meId = meId
        self.nameOf = nameOf
        self.onToggle = onToggle
        self.onClose = onClose
    }

    var body: some View {
        let total = reactions.reduce(0) { $0 + $1.userIds.count }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("reactions.reactions")).font(.system(size: 19, weight: .bold)).foregroundStyle(.dlInk)
                Spacer()
                Text(formatNumber(total)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.dlInkQuiet)
            }
            .padding(.bottom, 4)
            ForEach(reactions) { r in
                let mine = r.userIds.contains(meId)
                HStack(spacing: 12) {
                    Text(r.emoji)
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(mine ? Color.dlSealTint : Color.dlPaperLetter, in: Circle())
                        .accessibilityHidden(true)
                    Text(r.userIds.map(nameOf).filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.dlInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { onToggle(r.emoji, mine) } label: {
                        Text(mine ? t("emails.removeReaction") : "+ " + t("emails.addReaction"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(mine ? Color.dlInk : Color.dlOnSeal)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(mine ? Color.clear : Color.dlSeal, in: Capsule())
                            .overlay(Capsule().strokeBorder(mine ? Color.dlLine : Color.clear, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DLPressStyle(scale: 0.96))
                    .accessibilityLabel(mine ? t("emails.removeReactionLabel", ["emoji": r.emoji]) : t("emails.addReactionLabel", ["emoji": r.emoji]))
                }
                .frame(minHeight: 56)
                Divider()
            }
            EmojiInput(emoji: $picked, isEditing: $every) {
                Label(t("emails.anotherReaction"), systemImage: "face.smiling")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.dlSeal)
                    .frame(minHeight: 44)
            }
            .accessibilityAddTraits(.isButton)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onChange(of: picked) { _, emoji in
            guard !emoji.isEmpty else { return }
            picked = ""
            every = false
            if !reactions.contains(where: { $0.emoji == emoji && $0.userIds.contains(meId) }) { onToggle(emoji, false) }
        }
        .onChange(of: reactions.isEmpty) { _, empty in
            if empty { onClose() }
        }
    }
}

/// Optimistic send OS4: the red ⚠ disc where ↩ goes, opening the Not sent sheet. Always visible.
struct UnsentDisc: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.dlError)
                .frame(width: 28, height: 28)
                .background(Color.dlErrorTint, in: Circle())
                .overlay(Circle().stroke(Color.dlError.opacity(0.5), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(DLPressStyle(scale: 0.92))
        .accessibilityLabel(t("emails.notSentOptions"))
    }
}

/// OS5: why it failed, Retry (only when it can help) and Cancel.
struct UnsentSheet: View {
    let fail: EmailOutbox.Fail
    let reason: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(t("emails.notSentTitle")).font(.custom(DLFontName.literataSemiBold.name, size: 19, relativeTo: .title3))
            } icon: {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.dlError)
            }
            .accessibilityAddTraits(.isHeader)
            Text(reason).dlText(.callout).foregroundStyle(.dlInkQuiet)
            if fail.retryable {
                Button(t("emails.retry"), action: onRetry).buttonStyle(DLButtonStyle(.filled, fullWidth: true))
            }
            Button(t("emails.cancelEmail"), role: .destructive, action: onCancel).buttonStyle(DLButtonStyle(.danger, fullWidth: true))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

/// Stickers SK7: whether the sticker is a favourite, and the toggle.
struct StickerFavourite {
    let on: Bool
    let toggle: () -> Void
}
