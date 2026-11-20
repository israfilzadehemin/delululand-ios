import DLNetwork
@testable import DLUI
import Testing

/// Read ticks (doc "Delululand — Read Ticks" TK5–TK7, TK10; web Emails.test.tsx, Android ReadTicksTest).
@Suite("Read ticks")
struct ReadTicksTests {
    private func email(delivered: String? = nil, read: String? = nil) -> Email {
        Email(id: "e1", threadId: "t1", senderId: "1", text: "Hi", sentAt: "2026-11-20T14:16:00Z", deliveredAt: delivered, readAt: read)
    }

    @Test("The latest mark wins; read implies delivered")
    func state() {
        #expect(TickStatus.of(email()) == .sent)
        #expect(TickStatus.of(email(delivered: "2026-11-20T14:16:05Z")) == .delivered)
        #expect(TickStatus.of(email(delivered: "2026-11-20T14:16:05Z", read: "2026-11-20T14:17:00Z")) == .read)
        #expect(TickStatus.of(email(read: "2026-11-20T14:17:00Z")) == .read)
    }

    @Test("The list's lastStatus from the wire")
    func wire() {
        #expect(TickStatus.of(wire: "delivered") == .delivered)
        #expect(TickStatus.of(wire: nil) == nil)
        #expect(TickStatus.of(wire: "seen") == nil)
        #expect(TickStatus.read.labelKey == "emails.status.readLabel")
    }

    @Test("The card lists every state reached on mine, Sent only on the friend's")
    func card() {
        let e = email(delivered: "2026-11-20T14:16:05Z", read: "2026-11-20T14:17:00Z")
        #expect(ReadTicksSpec.rows(e, mine: true).map(\.status) == [.sent, .delivered, .read])
        #expect(ReadTicksSpec.rows(e, mine: true).last?.at == "2026-11-20T14:17:00Z")
        #expect(ReadTicksSpec.rows(e, mine: false).map(\.status) == [.sent])
        #expect(ReadTicksSpec.rows(email(), mine: true).map(\.status) == [.sent])
    }
}
