import Foundation
@testable import DLNetwork
import Testing

@Suite("Rich text")
struct DocTests {
    @Test("Paragraphs, lists and marks survive a round trip in the API's grammar")
    func roundTrip() throws {
        let json = """
        {"type":"doc","content":[
          {"type":"paragraph","content":[{"type":"text","text":"Dear "},{"type":"text","text":"Emin","marks":[{"type":"bold"},{"type":"underline"}]}]},
          {"type":"paragraph"},
          {"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"tea","marks":[{"type":"italic"}]}]}]}]}
        ]}
        """
        let doc = try JSONDecoder().decode(Doc.self, from: Data(json.utf8))
        #expect(doc.content.count == 3)
        #expect(doc.plainText == "Dear Emin\n\ntea")
        guard case let .paragraph(runs) = doc.content[0] else { Issue.record("not a paragraph"); return }
        #expect(runs[1].bold && runs[1].underline && !runs[1].italic)
        let again = try JSONDecoder().decode(Doc.self, from: JSONEncoder().encode(doc))
        #expect(again == doc)
        let encoded = String(decoding: try JSONEncoder().encode(Doc.of("")), as: UTF8.self)
        #expect(encoded.contains(#""type":"doc""#))
    }

    @Test("Whitespace-only documents count as empty (FS-W11)")
    func empty() {
        #expect(Doc.empty.isEmpty)
        #expect(Doc.of("  ", "\t").isEmpty)
        #expect(!Doc.of("hi").isEmpty)
    }
}

@Suite("Models")
struct ModelTests {
    @Test("Missing keys take the API's defaults")
    func defaults() throws {
        let json = """
        {"serverNow":"2026-11-12T10:00:00Z",
         "me":{"id":1,"nickname":"Emin"},
         "universe":{"id":3,"name":"Delulutopia"},
         "from":[{"id":7,"direction":"from","state":"DELIVERED","sentAt":"2026-11-12T08:00:00Z","windowEndsAt":"2026-11-12T08:05:00Z","arrivesAt":"2026-11-12T09:00:00Z"}]}
        """
        let home = try JSONDecoder().decode(Home.self, from: Data(json.utf8))
        #expect(home.me.draftEmpty)
        #expect(home.to.isEmpty)
        #expect(home.from.first?.id == 7)
        #expect(home.unreadCount == 0)
        #expect(!home.universe.isCreator)
        #expect(home.friendName == "your friend")
    }

    @Test("Null lists decode as empty")
    func nulls() throws {
        let json = #"{"id":1,"threadId":2,"senderId":3,"sentAt":"2026-11-12T10:00:00Z","attachments":null}"#
        let email = try JSONDecoder().decode(Email.self, from: Data(json.utf8))
        #expect(email.attachments.isEmpty)
        #expect(email.text == "")
    }
}

@Suite("Cookies")
struct CookieTests {
    @Test("The jar stores Set-Cookie, sends matching cookies and drops expired ones")
    func jar() throws {
        let jar = CookieStore(service: "dl.tests.\(UUID().uuidString)", inMemory: true)
        let url = URL(string: "https://test.delulutopia.com/api/auth/login")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Set-Cookie": "__Host-dl=abc; Path=/; Secure; HttpOnly; Max-Age=3600",
        ])!
        jar.store(from: response, url: url)
        #expect(jar.header(for: URL(string: "https://test.delulutopia.com/api/home")!) == "__Host-dl=abc")
        #expect(jar.header(for: URL(string: "https://example.com/")!) == nil)

        let gone = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Set-Cookie": "__Host-dl=; Path=/; Secure; Max-Age=0",
        ])!
        jar.store(from: gone, url: url)
        #expect(jar.header(for: url) == nil)
    }

    @Test("Refusals keep the API's code, message and extras")
    func refusal() {
        let body = Data(#"{"code":"DRAFT_CONFLICT","message":"A newer version…","serverVersion":9}"#.utf8)
        let error = APIClient.refusal(status: 409, data: body)
        #expect(error.code == "DRAFT_CONFLICT")
        #expect(error.extra["serverVersion"]?.int == 9)
        #expect(!error.isOffline)
        #expect(APIClient.refusal(status: 502, data: Data()).isOffline)
    }
}
