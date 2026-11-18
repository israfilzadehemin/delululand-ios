@testable import DLUI
import Foundation
import Testing

/// Clickable links (doc "Delululand — Links" LK2/LK5/LK7; web src/text/links.test.ts).
@Suite("Links")
struct LinksTests {
    private func links(_ s: String) -> [String] { Links.linkify(s).compactMap { $0.href == nil ? nil : "\($0.text)|\($0.href!)" } }

    @Test("Plain text stays one segment")
    func plain() {
        #expect(Links.linkify("hello there") == [Links.Segment("hello there")])
        #expect(Links.linkify("") == [Links.Segment("")])
    }

    @Test("http, https and www in order; the text round-trips")
    func finds() {
        let s = "a http://x.com b https://y.org/p?q=1#h c www.z.net d"
        #expect(links(s) == ["http://x.com|http://x.com", "https://y.org/p?q=1#h|https://y.org/p?q=1#h", "www.z.net|https://www.z.net"])
        #expect(Links.linkify(s).map(\.text).joined() == s)
    }

    @Test("Bare domains, emails and phone numbers stay text (LK2)")
    func bare() {
        #expect(!Links.hasLink("see site.com or me@mail.com or +48 123 456 789 file.txt"))
        #expect(!Links.hasLink("me@www.mail.com"))
    }

    @Test("Trailing punctuation stays outside (LK7)")
    func trailing() {
        #expect(links("see https://x.com.") == ["https://x.com|https://x.com"])
        #expect(links("really? www.x.com!?") == ["www.x.com|https://www.x.com"])
        #expect(links("\"https://x.com/a\",") == ["https://x.com/a|https://x.com/a"])
    }

    @Test("Balanced brackets stay, unbalanced go")
    func brackets() {
        #expect(links("(https://x.com/a)") == ["https://x.com/a|https://x.com/a"])
        let wiki = "https://en.wikipedia.org/wiki/Baku_(city)"
        #expect(links(wiki) == ["\(wiki)|\(wiki)"])
    }

    @Test("Right to left and new lines")
    func rtl() {
        #expect(Links.linkify("سلام https://x.com\nwww.y.com").compactMap { $0.href == nil ? nil : $0.text } == ["https://x.com", "www.y.com"])
    }

    @Test("Only http(s) with a dotted host opens (LK5)")
    func schemes() {
        #expect(!Links.hasLink("https:// and www."))
        #expect(Links.hrefOf("https://localhost") == nil)
        #expect(Links.hrefOf("javascript:alert(1)") == nil)
    }

    @Test("Attributed text gets a link and underline on the URL only")
    func attributed() {
        let a = AttributedString("go www.x.com now").withLinks()
        let linked = a.runs.filter { $0.link != nil }
        #expect(linked.count == 1)
        #expect(linked.first.map { String(a[$0.range].characters) } == "www.x.com")
        #expect(linked.first?.link == URL(string: "https://www.x.com"))
    }
}
