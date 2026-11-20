import DLNetwork
@testable import DLUI
import Testing

/// Bubble actions (doc "Delululand — Bubble Actions" BA4, BA7; web Emails.test.tsx, Android BubbleActionsTest).
@Suite("Bubble actions")
struct BubbleActionsTests {
    @Test("The pill shows the first three emojis in chip order and the total")
    func pill() {
        let chips = [
            Reaction(emoji: "☕", userIds: ["1", "2"]),
            Reaction(emoji: "🔥", userIds: ["2"]),
            Reaction(emoji: "❤️", userIds: ["1"]),
            Reaction(emoji: "😂", userIds: ["2"]),
        ]
        let p = BubbleActionsSpec.pill(chips)
        #expect(p.shown == ["☕", "🔥", "❤️"])
        #expect(p.total == 5)
    }

    @Test("The quick row is six: recents first, then the defaults")
    func quick() {
        #expect(BubbleActionsSpec.quick(recents: []) == ["❤️", "😂", "🥹", "😮", "😢", "🔥"])
        #expect(BubbleActionsSpec.quick(recents: ["🙏", "🔥"]) == ["🙏", "🔥", "❤️", "😂", "🥹", "😮"])
    }

    @Test("Long-press timing matches web and Android")
    func timing() {
        #expect(BubbleActionsSpec.longPress == 0.45)
        #expect(BubbleActionsSpec.slop == 10)
    }
}
