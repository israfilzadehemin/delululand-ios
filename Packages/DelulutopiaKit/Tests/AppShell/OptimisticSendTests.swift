import DLNetwork
@testable import FeatureEmails
import Foundation
import Testing

/// Optimistic send (doc "Delululand — Optimistic Send" OS3, OS5; web Emails.test.tsx, Android EmailOutboxTest).
@Suite("Optimistic send")
@MainActor
struct OptimisticSendTests {
    @Test("Offline, timeout and 5xx can be retried; refusals and credits cannot")
    func retryable() {
        #expect(EmailOutbox.classify(APIError(status: 0, code: APIError.offlineCode, message: "")).kind == .offline)
        #expect(EmailOutbox.classify(APIError(status: 0, code: APIError.offlineCode, message: "")).retryable)
        #expect(EmailOutbox.classify(APIError(status: 503, code: "HTTP_503", message: "")).retryable)
        #expect(EmailOutbox.classify(EmailOutbox.TimedOut()).kind == .timeout)
        #expect(!EmailOutbox.classify(APIError(status: 409, code: "NO_CREDITS", message: "")).retryable)
        let refused = EmailOutbox.classify(APIError(status: 422, code: "TOO_LONG", message: "Too long"))
        #expect(!refused.retryable)
        #expect(refused.message == "Too long")
    }

    @Test("The provisional bubble is stored like the API, with a local id and its attachments")
    func provisional() {
        let box = EmailOutbox()
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let att = Att(id: "a1", kind: "photo", url: "/p")
        let a = box.provisional(threadId: "t1", senderId: "u1", text: "  hi\r\nthere \n", attachments: [att], replyTo: nil, now: now)
        let b = box.provisional(threadId: "t1", senderId: "u1", text: "x", attachments: [], replyTo: nil, now: now)
        #expect(a.text == "hi\nthere")
        #expect(a.id.hasPrefix("local-"))
        #expect(a.id != b.id)
        #expect(a.attachments.map(\.id) == ["a1"])
    }
}
