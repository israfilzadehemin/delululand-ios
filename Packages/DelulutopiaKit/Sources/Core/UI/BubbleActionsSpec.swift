import CoreGraphics
import DLNetwork

/// Bubble actions (doc "Delululand — Bubble Actions"; web emails/bubbleGestures.ts): the numbers the
/// three apps share.
public enum BubbleActionsSpec {
    /// BA4: how long a finger rests before the layer opens (seconds), and how far it may drift (pt).
    public static let longPress: Double = 0.45
    public static let slop: CGFloat = 10
    /// BA7: emojis shown in the pill before the rest only count.
    public static let pillEmojis = 3
    /// R2: the quick row's six defaults.
    public static let quickDefaults = ["❤️", "😂", "🥹", "😮", "😢", "🔥"]

    /// BA7: the first ``pillEmojis`` emojis in chip order, and the total reactions.
    public static func pill(_ reactions: [Reaction]) -> (shown: [String], total: Int) {
        (Array(reactions.prefix(pillEmojis).map(\.emoji)), reactions.reduce(0) { $0 + $1.userIds.count })
    }

    /// BA4: the quick row: this phone's recents first, then the defaults, six in all.
    public static func quick(recents: [String]) -> [String] {
        var out: [String] = []
        for e in recents + quickDefaults where !out.contains(e) {
            out.append(e)
        }
        return Array(out.prefix(6))
    }
}
