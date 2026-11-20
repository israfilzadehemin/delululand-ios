@testable import DLUI
import Testing

/// iOS design audit (19 Nov 2026) F8: which routes start something new for the friend.
@Suite("New-item routes")
struct NewItemRouteTests {
    @Test("A fresh letter, discussion or email starts something new")
    func starts() {
        #expect(AppRoute.write().startsNew)
        #expect(AppRoute.composeDiscussion(editId: nil).startsNew)
        #expect(AppRoute.newEmail.startsNew)
    }

    @Test("Editing, replying and reading never count as new")
    func notNew() {
        #expect(!AppRoute.write(editId: "a").startsNew)
        #expect(!AppRoute.write(replyTo: "b").startsNew)
        #expect(!AppRoute.composeDiscussion(editId: "c").startsNew)
        #expect(!AppRoute.letter("d").startsNew)
        #expect(!AppRoute.thread("e").startsNew)
        #expect(!AppRoute.profile.startsNew)
    }
}
