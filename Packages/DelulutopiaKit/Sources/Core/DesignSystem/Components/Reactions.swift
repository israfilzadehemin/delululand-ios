import DLI18n
import SwiftUI

/// A reaction toggle chip (doc "Delululand — Reactions"): the emoji, a count when both citizens
/// chose it, and the viewer's own reaction marked with the lavender fill and a seal ring.
public struct DLReactionChip: View {
    let emoji: String
    let count: Int
    let mine: Bool
    let compact: Bool
    let action: () -> Void

    /// `compact` is the 26 pt chip under comments; the default is 30 pt.
    public init(_ emoji: String, count: Int = 1, mine: Bool, compact: Bool = false, action: @escaping () -> Void) {
        self.emoji = emoji
        self.count = count
        self.mine = mine
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: compact ? 13 : 15))
                if count > 1 {
                    Text("\(count)")
                        .dlText(.buttonSmall)
                        .foregroundStyle(.dlInk)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .frame(height: compact ? 26 : 30)
            .background(mine ? Color.dlSealTint : Color.dlPaperLetter, in: Capsule())
            .overlay(Capsule().strokeBorder(mine ? Color.dlSeal : Color.dlLine, lineWidth: mine ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(DLPressStyle(scale: 0.92))
        .accessibilityLabel(count > 1 ? "\(emoji) \(count)" : emoji)
        .accessibilityAddTraits(mine ? .isSelected : [])
    }
}

/// The face-plus button that opens the reaction row.
public struct DLAddReactionButton: View {
    let compact: Bool
    let action: () -> Void

    public init(compact: Bool = false, action: @escaping () -> Void) {
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "face.smiling")
                .font(.system(size: compact ? 14 : 16, weight: .regular))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: compact ? 7 : 8, weight: .bold))
                        .offset(x: 4, y: -3)
                }
                .foregroundStyle(.dlInkQuiet)
                .frame(width: compact ? 32 : 36, height: compact ? 26 : 30)
                .overlay(Capsule().strokeBorder(.dlLine, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(DLPressStyle(scale: 0.92))
        .accessibilityLabel(t("reactions.addAReaction"))
    }
}
