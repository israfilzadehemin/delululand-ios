import SafariServices
import SwiftUI

/// Links in what citizens write (doc "Delululand — Links", web text/links.ts): `http://`, `https://`
/// and `www.` runs become links when shown; nothing is stored. Bare domains, emails and phone numbers
/// stay text. Trailing `. , ! ? : ; ' "` and an unbalanced closing bracket stay outside the link.
public enum Links {
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let href: String?
        public init(_ text: String, href: String? = nil) {
            self.text = text
            self.href = href
        }
    }

    private static let trailing: Set<Character> = [".", ",", "!", "?", ":", ";", "'", "\"", "’", "”", "»", "…"]
    private static let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    private static func trim(_ raw: Substring) -> Substring {
        var s = raw
        while let last = s.last {
            if trailing.contains(last) {
                s = s.dropLast()
            } else if let open = pairs[last], s.count(where: { $0 == last }) > s.count(where: { $0 == open }) {
                s = s.dropLast()
            } else {
                break
            }
        }
        return s
    }

    /// The URL a link opens: `www.` gets `https://`; only http(s) with a dotted host is opened (LK5).
    public static func hrefOf(_ text: String) -> String? {
        let url = text.lowercased().hasPrefix("www.") ? "https://\(text)" : text
        guard let m = url.firstMatch(of: /^https?:\/\/(?:[^\/?#@]*@)?([^\/?#:]+)/.ignoresCase()) else { return nil }
        let host = m.1
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".") ? url : nil
    }

    /// Plain and link segments in order; joining every `text` gives the input back.
    public static func linkify(_ input: String) -> [Segment] {
        var out: [Segment] = []
        var at = input.startIndex
        for m in input.matches(of: /\b(?:https?:\/\/|www\.)[^\s<>]+/.ignoresCase()) {
            let start = m.range.lowerBound
            if start > input.startIndex {
                let before = input[input.index(before: start)]
                if "/@.-_".contains(before) || before.isLetter || before.isNumber { continue }
            }
            if start < at { continue }
            let text = trim(m.output)
            guard let href = hrefOf(String(text)) else { continue }
            if start > at { out.append(Segment(String(input[at ..< start]))) }
            out.append(Segment(String(text), href: href))
            at = text.endIndex
        }
        if at < input.endIndex || out.isEmpty { out.append(Segment(String(input[at...]))) }
        return out
    }

    public static func hasLink(_ input: String) -> Bool { linkify(input).contains { $0.href != nil } }
}

public extension AttributedString {
    /// This text with its links made tappable and underlined (LK6); the link colour comes from `.tint`.
    func withLinks() -> AttributedString {
        let segments = Links.linkify(String(characters))
        guard segments.contains(where: { $0.href != nil }) else { return self }
        var out = self
        var at = out.startIndex
        for s in segments {
            let end = out.characters.index(at, offsetBy: s.text.count)
            if let href = s.href, let url = URL(string: href) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") {
                out[at ..< end].link = url
                out[at ..< end].underlineStyle = .single
            }
            at = end
        }
        return out
    }
}

public extension Text {
    /// Plain text (comments, emails, the board note) with its links tappable; add `.tint(ink)` so the
    /// link keeps the surrounding ink.
    init(linking text: String) {
        self.init(AttributedString(text).withLinks())
    }
}

/// LK4: http(s) links open in Safari over the app; anything else (Settings) goes to the system.
private struct LinkSheet: ViewModifier {
    @State private var page: Page?

    struct Page: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .systemAction }
                page = Page(url: url)
                return .handled
            })
            .fullScreenCover(item: $page) { p in
                SafariView(url: p.url).ignoresSafeArea()
            }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context _: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

public extension View {
    /// At the app's root: links in citizens' text open in Safari inside the app.
    func opensLinksInApp() -> some View { modifier(LinkSheet()) }
}
