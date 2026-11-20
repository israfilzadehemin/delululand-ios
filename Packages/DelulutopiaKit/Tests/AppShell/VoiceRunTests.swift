import DLNetwork
@testable import DLUI
import Testing

/// Earpiece Playback EP7 (doc "Delululand — Earpiece Playback"): which emails' voice notes play on.
@Suite("Voice run")
struct VoiceRunTests {
    private func email(_ id: String, _ sender: String, _ voices: [String], photo: Bool = false) -> Email {
        var atts = voices.map { Att(id: $0, kind: "audio", url: "/media/\($0)") }
        if photo { atts.append(Att(id: "p\(id)", kind: "photo", url: "/media/p\(id)")) }
        return Email(id: id, threadId: "t", senderId: sender, text: "", sentAt: "2026-11-20T10:00:00Z", attachments: atts)
    }

    // Oldest first, as the thread shows them.
    private var emails: [Email] {
        [
            email("1", "me", ["z"]),
            email("2", "me", [], photo: true),
            email("3", "me", ["a"]),
            email("4", "me", ["b1", "b2"]),
            email("5", "me", ["c"]),
            email("6", "friend", ["f1"]),
        ]
    }

    @Test("Follows the same sender's next emails in chat order")
    func follows() {
        #expect(VoiceRun.after(emails, index: 2) == ["/media/b1", "/media/b2", "/media/c"])
    }

    @Test("Stops at the friend's email")
    func friend() {
        #expect(VoiceRun.after(emails, index: 4).isEmpty)
    }

    @Test("Stops at an email without a voice note")
    func noVoice() {
        #expect(VoiceRun.after(emails, index: 0).isEmpty)
    }

    @Test("An email whose voice notes expired ends the run")
    func expired() {
        let gone = Email(id: "x", threadId: "t", senderId: "me", text: "", sentAt: "2026-11-20T10:00:00Z",
                         attachments: [Att(id: "e", kind: "audio", url: "/media/e", expired: true)])
        #expect(VoiceRun.after([email("8", "me", ["now"]), gone, email("9", "me", ["late"])], index: 0).isEmpty)
    }

    @Test("The newest email has nothing after it")
    func newest() {
        #expect(VoiceRun.after(emails, index: 5).isEmpty)
    }
}
