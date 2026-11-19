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
         "me":{"id":"1","nickname":"Emin"},
         "universe":{"id":"3","name":"Delulutopia"},
         "from":[{"id":"7","direction":"from","state":"DELIVERED","sentAt":"2026-11-12T08:00:00Z","windowEndsAt":"2026-11-12T08:05:00Z","arrivesAt":"2026-11-12T09:00:00Z"}]}
        """
        let home = try JSONDecoder().decode(Home.self, from: Data(json.utf8))
        #expect(home.me.draftEmpty)
        #expect(home.to.isEmpty)
        #expect(home.from.first?.id == "7")
        #expect(home.unreadCount == 0)
        #expect(!home.universe.isCreator)
        #expect(home.friendName == "your friend")
    }

    @Test("Null lists decode as empty")
    func nulls() throws {
        let json = #"{"id":"1","threadId":"2","senderId":"3","sentAt":"2026-11-12T10:00:00Z","attachments":null}"#
        let email = try JSONDecoder().decode(Email.self, from: Data(json.utf8))
        #expect(email.attachments.isEmpty)
        #expect(email.text == "")
    }

    @Test("A reply carries its quote; a thread row says whether its newest is a reply (Email Replies RE11, RE13)")
    func replies() throws {
        let json = #"{"id":"9","threadId":"2","senderId":"3","sentAt":"2026-11-19T10:00:00Z","replyTo":{"id":"1","senderId":"4","media":{"photos":1},"thumbUrl":"/t","sentAt":"2026-11-19T09:00:00Z"}}"#
        let email = try JSONDecoder().decode(Email.self, from: Data(json.utf8))
        #expect(email.replyTo?.id == "1")
        #expect(email.replyTo?.text == nil)
        #expect(email.replyTo?.media?.photos == 1)
        #expect(email.replyTo?.media?.videos == 0)
        let plain = try JSONDecoder().decode(Email.self, from: Data(#"{"id":"1","threadId":"2","senderId":"3","sentAt":"2026-11-19T10:00:00Z"}"#.utf8))
        #expect(plain.replyTo == nil)
        let row = #"{"id":"t","subject":"S","startedBy":"a","createdAt":"x","lastEmailAt":"y"}"#
        #expect(try JSONDecoder().decode(ThreadRow.self, from: Data(row.utf8)).lastIsReply == false)
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

    @Test("Deletion previews decode; missing counts are zero")
    func deletionPreview() throws {
        let json = #"{"scope":"UNIVERSE","universe":"Moonbase","friend":"Leyla","counts":{"letters":4,"voice":1}}"#
        let p = try Coders.decoder().decode(DeletionPreview.self, from: Data(json.utf8))
        #expect(p.counts.of("letters") == 4)
        #expect(p.counts.of("voice") == 1)
        #expect(p.counts.of("doodles") == 0)
        #expect(p.friend == "Leyla")
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

@Suite("URLs")
struct URLTests {
    private let client = APIClient(
        baseURL: URL(string: "https://test.delulutopia.com")!,
        cookies: CookieStore(service: "dl.tests.\(UUID().uuidString)", inMemory: true)
    )

    @Test("A path's own query stays a query (board image ?u=)")
    func pathQuery() {
        let url = client.url("/api/board/image/3?u=0b6c1a52-7d4e-4f0a-9a51-3f2f1c0e9d11")
        #expect(url.absoluteString == "https://test.delulutopia.com/api/board/image/3?u=0b6c1a52-7d4e-4f0a-9a51-3f2f1c0e9d11")
        #expect(url.path() == "/api/board/image/3")
    }

    @Test("A path's query comes before the extra query; plain paths are unchanged")
    func merged() {
        #expect(client.url("/api/x?u=1", query: ["version": "2"]).absoluteString == "https://test.delulutopia.com/api/x?u=1&version=2")
        #expect(client.url("api/attachments/abc").absoluteString == "https://test.delulutopia.com/api/attachments/abc")
        #expect(client.url("/api/board/reaction", query: ["version": "4"]).absoluteString == "https://test.delulutopia.com/api/board/reaction?version=4")
    }
}

@Suite("Attachment retention")
struct RetentionDecodingTests {
    @Test("An expired file, a quote's expired thumb and the config's days decode; older payloads default to live (AR7, AR9, AR14)")
    func decodes() throws {
        let att = try JSONDecoder().decode(Att.self, from: Data(#"{"id":"a","kind":"photo","url":"/api/attachments/a","position":0,"expired":true}"#.utf8))
        #expect(att.expired)
        let old = try JSONDecoder().decode(Att.self, from: Data(#"{"id":"b","kind":"audio","url":"/api/attachments/b","position":1}"#.utf8))
        #expect(!old.expired)
        let quote = try JSONDecoder().decode(
            EmailQuote.self,
            from: Data(#"{"id":"q","senderId":"s","thumbUrl":null,"thumbExpired":true,"sentAt":"2026-11-20T10:00:00.000Z"}"#.utf8)
        )
        #expect(quote.thumbExpired && quote.thumbUrl == nil)
        let settings = try JSONDecoder().decode(
            ServerSettings.self,
            from: Data(#"{"delay":"PT1H","window":"PT5M","env":"prod","serverNow":"x","retention":{"letterDays":90,"otherDays":30}}"#.utf8)
        )
        #expect(settings.retention?.letterDays == 90 && settings.retention?.otherDays == 30)
    }
}
