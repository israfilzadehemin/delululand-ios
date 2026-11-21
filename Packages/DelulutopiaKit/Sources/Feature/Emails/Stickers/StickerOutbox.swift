import DLData
import DLNetwork
import Foundation
import Observation

/// A sticker in the air (doc "Delululand — Stickers" FS-SK6; web stickers/outbox.ts): the bubble
/// shows at once; the send runs behind it. Unlike a text reply nothing is held — the draft stays as
/// it is (SK3) and several can be in the air. Retry keeps the client id, so the server never makes a
/// second email.
@MainActor
@Observable
final class StickerOutbox {
    static let shared = StickerOutbox()

    struct Entry: Equatable, Sendable {
        let threadId: PublicID
        /// The provisional email (a `local-` id) drawn as a sticker.
        let email: Email
        let clientId: String
        var status: EmailOutbox.Status
        var fail: EmailOutbox.Fail?
    }

    /// By local id; `order` keeps the order they were sent in.
    private(set) var entries: [PublicID: Entry] = [:]
    @ObservationIgnored private var order: [PublicID] = []
    @ObservationIgnored private var listeners: [UUID: (PublicID, Email, EmailCredits) -> Void] = [:]
    @ObservationIgnored private var api: API?
    @ObservationIgnored private var seq = 0

    func of(_ threadId: PublicID) -> [Entry] { order.compactMap { entries[$0] }.filter { $0.threadId == threadId } }

    var sendingCount: Int { entries.values.filter { $0.status == .sending }.count }

    /// Sent: the thread swaps the provisional bubble for the real email.
    func listen(_ fn: @escaping (PublicID, Email, EmailCredits) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = fn
        return id
    }

    func unlisten(_ id: UUID) { listeners[id] = nil }

    @discardableResult
    func send(threadId: PublicID, senderId: PublicID, sticker: StickerRef, replyTo: EmailQuote?, api: API, now: Date = Date()) -> Email {
        self.api = api
        seq += 1
        let ms = Int(now.timeIntervalSince1970 * 1000)
        let email = Email(
            id: "local-s\(String(ms, radix: 36))-\(seq)",
            threadId: threadId,
            senderId: senderId,
            text: "",
            sentAt: DLTime.iso(now),
            replyTo: replyTo,
            sticker: sticker
        )
        entries[email.id] = Entry(threadId: threadId, email: email, clientId: UUID().uuidString.lowercased(), status: .sending)
        order.append(email.id)
        run(email.id)
        return email
    }

    func retry(_ local: PublicID) {
        guard var e = entries[local], e.status == .failed else { return }
        e.status = .sending
        e.fail = nil
        entries[local] = e
        run(local)
    }

    func cancel(_ local: PublicID) {
        guard let e = entries[local], e.status == .failed else { return }
        entries[local] = nil
        order.removeAll { $0 == local }
    }

    private func run(_ local: PublicID) {
        guard let e = entries[local], let sticker = e.email.sticker, let api else { return }
        Task {
            do {
                let s = try await EmailOutbox.withTimeout {
                    try await api.sendSticker(threadId: e.threadId, stickerId: sticker.id, replyToId: e.email.replyTo?.id, clientId: e.clientId)
                }
                guard entries[local] != nil else { return }
                entries[local] = nil
                order.removeAll { $0 == local }
                listeners.values.forEach { $0(e.threadId, s.email, s.credits) }
            } catch {
                guard var cur = entries[local] else { return }
                cur.status = .failed
                cur.fail = EmailOutbox.classify(error)
                entries[local] = cur
            }
        }
    }

    /// Tests only.
    func reset() {
        entries = [:]
        order = []
    }
}
