import DLData
import DLNetwork
import Foundation

/// A fixture API for screenshots (the Android `tools/parity/server.mjs`, ported): the same sample
/// universe (Delulutopia; Emin in Warsaw, Leyla in Tehran) served from memory through URLProtocol.
public final class FixtureServer: URLProtocol, @unchecked Sendable {
    public struct State: Sendable {
        /// A session cookie that the API accepts.
        public var auth = true
        /// This device holds the entry pass (cards instead of the landing).
        public var entry = true
        /// The creator is alone in the universe (Universe U8).
        public var alone = false
        /// No letters, discussions or emails.
        public var empty = false
        public var noCredits = false

        public init() {}
    }

    public static let host = "fixture.delulutopia.test"
    public static let baseURL = URL(string: "https://\(host)")!
    nonisolated(unsafe) public static var state = State()

    override public class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == host
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let url = request.url else { return }
        let (status, body, type) = Self.respond(method: request.httpMethod ?? "GET", url: url)
        var headers = [
            "Content-Type": type,
            "X-Server-Time": String(Int(Date().timeIntervalSince1970 * 1000)),
        ]
        if url.path() == "/api/entry" || url.path() == "/api/auth/login" {
            headers["Set-Cookie"] = "__Host-dl=fixture; Path=/; Secure; HttpOnly; Max-Age=3600"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}

    // MARK: Data

    static func iso(_ minutes: Double) -> String {
        DLTime.iso(Date().addingTimeInterval(minutes * 60))
    }

    static func doc(_ paragraphs: String...) -> [String: Any] {
        ["type": "doc", "content": paragraphs.map { ["type": "paragraph", "content": [["type": "text", "text": $0]]] }]
    }

    static var me: [String: Any] {
        [
            "id": 1, "nickname": "Emin", "avatarUrl": "/api/m/emin.jpg", "mood": "HAPPY", "moodSetAt": iso(-120),
            "moodEmoji": "😊", "moodLabel": "Happy", "timezone": "Europe/Warsaw", "firstName": "Emin",
            "lastName": "Israfilzade", "draftEmpty": false, "discussionDraftEmpty": true,
        ]
    }

    static var friend: [String: Any] {
        [
            "id": 2, "nickname": "Leyla", "mood": "CALM", "moodSetAt": iso(-25), "moodEmoji": "🍵",
            "moodLabel": "Calm", "timezone": "Asia/Tehran", "firstName": "Leyla",
        ]
    }

    static var stamp: [String: Any] { ["slug": "tulip", "name": "Tulip", "imageUrl": "/api/m/stamp.svg"] }

    static var letterRows: (from: [[String: Any]], to: [[String: Any]]) {
        if state.empty { return ([], []) }
        return (
            [
                ["id": 11, "direction": "from", "state": "DELIVERED", "sentAt": iso(-180), "windowEndsAt": iso(-175), "arrivesAt": iso(-60),
                 "firstLine": "Dear Emin, the week went by slower than I expected", "media": ["photos": 2, "audios": 1],
                 "moodEmoji": "🍵", "moodLabel": "Calm", "stamp": stamp],
                ["id": 12, "direction": "from", "state": "IN_TRANSIT", "sentAt": iso(-32), "windowEndsAt": iso(-27), "arrivesAt": iso(28), "stamp": stamp],
                ["id": 10, "direction": "from", "state": "READ", "sentAt": iso(-3000), "windowEndsAt": iso(-2995), "arrivesAt": iso(-2940),
                 "readAt": iso(-2900), "firstLine": "The tulips are out", "stamp": stamp],
            ],
            [
                ["id": 21, "direction": "to", "state": "IN_REACH", "sentAt": iso(-2), "windowEndsAt": iso(40), "arrivesAt": iso(95),
                 "firstLine": "Saturday works for me", "stamp": stamp],
                ["id": 20, "direction": "to", "state": "DELIVERED", "sentAt": iso(-200), "windowEndsAt": iso(-195), "arrivesAt": iso(-140),
                 "firstLine": "Here is the recipe you asked about", "stamp": stamp],
                ["id": 19, "direction": "to", "state": "READ", "sentAt": iso(-5000), "windowEndsAt": iso(-4995), "arrivesAt": iso(-4940),
                 "readAt": iso(-4800), "firstLine": "Good morning from Kraków", "stamp": stamp],
            ]
        )
    }

    static var home: [String: Any] {
        let rows = letterRows
        var h: [String: Any] = [
            "serverNow": iso(0), "me": me, "from": rows.from, "to": rows.to,
            "unreadCount": 1, "discussionsUnseen": 1,
            "newDiscussions": [["id": 31, "title": "Weekend in Zakopane?", "arrivesAt": iso(-30)]],
            "emailsUnread": 2, "emailsReacted": 1,
            "newEmails": [["id": 71, "threadId": 41, "subject": "Tickets for Saturday", "sentAt": iso(-20)]],
            "emailCredits": ["limit": 100, "used": 4, "left": 96, "renewsAt": iso(600)],
            "boardNew": true, "notifyPrefs": ["paused": false, "enabled": ["letter.arrived"]],
            "universe": ["id": 1, "name": "Delulutopia", "isCreator": true, "waiting": state.alone],
        ]
        if !state.alone { h["friend"] = friend }
        if !state.empty {
            h["board"] = [
                "version": 7, "authorId": 2, "createdAt": iso(-120), "url": "/api/m/board.png", "reaction": "heart",
                "comment": ["text": "this sun is literally me today", "createdAt": iso(-100)],
            ]
        }
        return h
    }

    static func att(_ id: Int, _ kind: String, _ position: Int) -> [String: Any] {
        var a: [String: Any] = [
            "id": "a\(id)", "kind": kind, "url": kind == "audio" ? "/api/m/voice.m4a" : "/api/m/photo.jpg",
            "thumbUrl": "/api/m/photo.jpg", "width": 1200, "height": 900, "position": position,
        ]
        if kind == "audio" { a["durationMs"] = 42000 }
        return a
    }

    static func letter(_ id: Int) -> [String: Any] {
        let rows = letterRows
        var r = (rows.from + rows.to).first { ($0["id"] as? Int) == id } ?? rows.from.first ?? [:]
        let from = (r["direction"] as? String) == "from"
        r["body"] = doc(
            "Dear Emin,",
            "the week went by slower than I expected. The tulips by the window finally opened, and I kept thinking you would laugh at how proud I am of them.",
            "Write soon."
        )
        r["attachments"] = from ? [att(1, "photo", 0), att(2, "photo", 1), att(3, "audio", 2)] : []
        r["canEdit"] = (r["state"] as? String) == "IN_REACH"
        r["canCancel"] = (r["state"] as? String) == "IN_REACH"
        if from {
            r["replyTo"] = ["id": 20, "direction": "to", "sentAt": iso(-200), "firstLine": "Here is the recipe you asked about"]
        }
        return r
    }

    static var discussionRows: [[String: Any]] {
        [
            ["id": 31, "authorId": 2, "mine": false, "color": "lemon", "state": "ARRIVED", "postedAt": iso(-120), "windowEndsAt": iso(-115),
             "arrivesAt": iso(-30), "title": "Weekend in Zakopane?", "firstLine": "We could take the morning train and", "commentCount": 4,
             "lastCommentAt": iso(-10), "isNew": true, "unseenComments": 2, "activityAt": iso(-10)],
            ["id": 32, "authorId": 1, "mine": true, "color": "sky", "state": "IN_REACH", "postedAt": iso(-1), "windowEndsAt": iso(40),
             "arrivesAt": iso(155), "title": "Books for the winter", "firstLine": "A list, in no order", "activityAt": iso(-1)],
            ["id": 33, "authorId": 2, "mine": false, "color": "pink", "state": "IN_TRANSIT", "postedAt": iso(-20), "windowEndsAt": iso(-15),
             "arrivesAt": iso(40)],
            ["id": 30, "authorId": 1, "mine": true, "color": "mint", "state": "ARRIVED", "postedAt": iso(-3000), "windowEndsAt": iso(-2995),
             "arrivesAt": iso(-2940), "title": "Plants", "firstLine": "The basil survived", "commentCount": 9, "lastCommentAt": iso(-900),
             "media": ["photos": 1, "audios": 0], "activityAt": iso(-900)],
        ]
    }

    static var comments: [[String: Any]] {
        [
            ["id": 301, "authorId": 1, "text": "Yes! Let me check the trains.", "createdAt": iso(-60), "reactions": [["emoji": "❤️", "userIds": [2]]]],
            ["id": 302, "authorId": 2, "text": "The 7:10 one is the scenic route", "createdAt": iso(-30)],
            ["id": 303, "authorId": 1, "text": "Booked.", "createdAt": iso(-10), "editedAt": iso(-8)],
        ]
    }

    static func discussion(_ id: Int) -> [String: Any] {
        var r = discussionRows.first { ($0["id"] as? Int) == id } ?? discussionRows[0]
        let mine = r["mine"] as? Bool ?? false
        r["title"] = r["title"] ?? "Untitled"
        r["body"] = doc("We could take the morning train and stay two nights.", "I found a small place near the market.")
        r["attachments"] = [att(9, "photo", 0)]
        r["canCancel"] = (r["state"] as? String) == "IN_REACH"
        r["comments"] = ["items": comments]
        r["reactions"] = [["emoji": "😍", "userIds": [1]]]
        r["canEdit"] = mine
        r["canDelete"] = mine
        r["canArchive"] = (r["state"] as? String) == "ARRIVED"
        r["canUnarchive"] = false
        return r
    }

    static var threads: [[String: Any]] {
        [
            ["id": 41, "subject": "Tickets for Saturday", "startedBy": 2, "createdAt": iso(-300), "lastEmailAt": iso(-20), "lastSenderId": 2,
             "lastText": "Got them! Row 7, seats 12 and 13. Bring the scarf", "emailCount": 4, "unread": 2],
            ["id": 42, "subject": "Recipe, finally", "startedBy": 1, "createdAt": iso(-400), "lastEmailAt": iso(-112), "lastSenderId": 1,
             "lastMedia": ["photos": 0, "audios": 0, "videos": 1], "emailCount": 2, "unread": 0, "unseenReactions": 1,
             "lastReaction": ["userId": 2, "emoji": "🤩", "target": "email", "onMine": true, "media": "video", "at": iso(-60)]],
            ["id": 43, "subject": "Our playlist", "startedBy": 2, "createdAt": iso(-5000), "lastEmailAt": iso(-4000), "lastSenderId": 2,
             "lastText": "Added three songs, one of them is a joke, guess which", "emailCount": 9, "unread": 0],
            ["id": 44, "subject": "Passport photos", "startedBy": 1, "createdAt": iso(-8000), "lastEmailAt": iso(-7000), "lastSenderId": 1,
             "lastMedia": ["photos": 2, "audios": 0, "videos": 0], "emailCount": 3, "unread": 0],
        ]
    }

    static var emails: [[String: Any]] {
        [
            ["id": 74, "threadId": 41, "senderId": 2, "text": "Got them! Row 7, seats 12 and 13. Bring the scarf", "sentAt": iso(-20),
             "attachments": [att(5, "photo", 0)], "reactions": []],
            ["id": 73, "threadId": 41, "senderId": 1, "text": "Can you check if there are two seats together?", "sentAt": iso(-90),
             "readAt": iso(-60), "attachments": [], "reactions": [["emoji": "👍", "userIds": [2]]]],
            ["id": 72, "threadId": 41, "senderId": 2, "text": "There is a concert on Saturday, want to go?", "sentAt": iso(-200),
             "attachments": [att(6, "audio", 0)]],
        ]
    }

    static var notifications: [String: Any] {
        ["paused": false, "sections": [
            ["key": "letters", "enabled": true, "events": [
                ["key": "letter.arrived", "enabled": true, "defaultOn": true],
                ["key": "letter.incoming", "enabled": false, "defaultOn": false],
                ["key": "letter.read", "enabled": true, "defaultOn": true],
            ]],
            ["key": "discussions", "enabled": true, "events": [
                ["key": "discussion.arrived", "enabled": true, "defaultOn": true],
                ["key": "discussion.comment", "enabled": true, "defaultOn": true],
                ["key": "discussion.reaction", "enabled": false, "defaultOn": true],
            ]],
            ["key": "emails", "enabled": false, "events": [
                ["key": "email.new", "enabled": true, "defaultOn": true],
                ["key": "email.reaction", "enabled": true, "defaultOn": true],
            ]],
        ]]
    }

    static let stampSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="60" height="72" viewBox="0 0 60 72"><rect width="60" height="72" fill="#fbf7ee"/><rect x="5" y="5" width="50" height="62" fill="#e3b8a6"/><circle cx="30" cy="34" r="12" fill="#b23a3a"/></svg>
    """

    static func media(_ name: String) -> Data? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Media") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
    }

    static var entryView: [String: Any] {
        [
            "name": "Delulutopia",
            "welcome": "Welcome to our little universe.\n\nLetters take an hour to arrive, so write slowly.",
            "canJoin": false,
            "users": [
                ["id": 1, "nickname": "Emin", "avatarUrl": "/api/m/emin.jpg", "hasPin": true] as [String: Any],
                ["id": 2, "nickname": "Leyla", "hasPin": true] as [String: Any],
            ],
        ]
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func respond(method: String, url: URL) -> (Int, Data, String) {
        let path = url.path()
        let query = url.query() ?? ""
        let refusal: (Int, String, String) -> (Int, Data, String) = { status, code, message in
            (status, json(["code": code, "message": message]), "application/json")
        }
        if path.hasPrefix("/api/m/") {
            let file = String(path.dropFirst(7))
            if file == "stamp.svg" { return (200, Data(stampSVG.utf8), "image/svg+xml") }
            if let data = media(file) { return (200, data, file.hasSuffix(".png") ? "image/png" : "image/jpeg") }
            return (404, Data(), "text/plain")
        }
        if method != "GET" { return (204, Data(), "application/json") }
        func ok(_ value: [String: Any]) -> (Int, Data, String) { (200, json(value), "application/json") }
        switch path {
        case "/api/config":
            return ok(["delay": "PT60M", "window": "PT5M", "discussionDelay": "PT120M", "testTiming": false, "env": "fixture",
                       "serverNow": iso(0), "emailDailyCredits": 100])
        case "/api/universe/entry":
            return state.entry ? ok(entryView) : refusal(401, "ENTRY_REQUIRED", "Enter the key first")
        case "/api/universe":
            return ok(["id": 1, "name": "Delulutopia", "welcome": entryView["welcome"] as Any, "creator": ["id": 1, "username": "Emin"],
                       "isCreator": true, "codeRotatedAt": iso(-60 * 24 * 5)])
        case "/api/home/counts":
            return ok(["unreadCount": 1, "discussionsUnseen": 1, "emailsUnread": 2, "emailsReacted": 1, "boardNew": true])
        case "/api/home":
            return state.auth ? ok(home) : refusal(401, "NO_SESSION", "Log in")
        case "/api/letters":
            let rows = letterRows
            let items = (rows.from + rows.to).sorted { ($0["sentAt"] as? String ?? "") > ($1["sentAt"] as? String ?? "") }
            return ok(["items": items])
        case "/api/draft":
            return ok(["body": doc("Dear Leyla,", "the trains are booked. I will bring the scarf, promise."),
                       "attachments": [att(7, "photo", 0), att(8, "audio", 1)], "pinnedLetterId": 11, "stamp": stamp,
                       "version": 3, "savedAt": iso(-1)])
        case "/api/stamps":
            let stamps = (0..<12).map { i -> [String: Any] in
                ["slug": "s\(i)", "name": "Stamp \(i)", "imageUrl": "/api/m/stamp.svg", "keywords": [], "theme": i % 2 == 0 ? "cities" : "flowers", "sort": i]
            }
            return ok(["themes": [["slug": "flowers", "name": "Flowers", "sort": 1], ["slug": "cities", "name": "Cities", "sort": 2]],
                       "stamps": stamps, "recent": ["s1", "s2"]])
        case "/api/moods":
            let moods: [[String: Any]] = Moods.defaults.map { m -> [String: Any] in ["key": m.key, "emoji": m.emoji, "label": m.label, "custom": false] }
                + [["key": "c1", "emoji": "🍕", "label": "Pizza night", "custom": true]]
            return ok(["limit": 48, "moods": moods])
        case "/api/discussions/draft":
            return ok(["title": "", "color": "lemon", "body": doc(), "attachments": [], "version": 1])
        case "/api/discussions":
            let archived = query.contains("archived=true")
            return ok(["items": state.empty || archived ? [] : discussionRows, "archivedCount": 2])
        case "/api/emails/credits":
            return ok(["limit": 100, "used": 4, "left": state.noCredits ? 0 : 96, "renewsAt": iso(600)])
        case "/api/emails/threads":
            return ok(["items": state.empty ? [] : threads])
        case "/api/me/profile":
            return ok(["id": 1, "username": "Emin", "firstName": "Emin", "lastName": "Israfilzade", "timezone": "Europe/Warsaw",
                       "avatarUrl": "/api/m/emin.jpg"])
        case "/api/me/notifications":
            return ok(notifications)
        case "/api/events":
            return (204, Data(), "text/event-stream")
        default:
            break
        }
        let parts = path.split(separator: "/").map(String.init)
        if parts.count == 3, parts[1] == "letters", let id = Int(parts[2]) { return ok(letter(id)) }
        if parts.count == 4, parts[1] == "discussions", parts[3] == "comments" { return ok(["items": comments]) }
        if parts.count == 3, parts[1] == "discussions", let id = Int(parts[2]) { return ok(discussion(id)) }
        if parts.count >= 4, parts[1] == "emails", parts[2] == "drafts" {
            return ok(["subject": "", "text": "", "attachments": [], "version": 1])
        }
        if parts.count == 5, parts[1] == "emails", parts[4] == "emails" { return ok(["items": []]) }
        if parts.count == 4, parts[1] == "emails", parts[2] == "threads", let id = Int(parts[3]) {
            let thread = threads.first { ($0["id"] as? Int) == id } ?? threads[0]
            return ok(["thread": thread, "emails": ["items": emails, "olderCursor": "x"]])
        }
        return refusal(404, "NOT_FOUND", "Not found \(path)")
    }
}

/// A backend wired to the fixture server, for screenshot tests.
@MainActor
public enum FixtureBackend {
    public static func make(state: FixtureServer.State = .init(), theme: ThemeMode = .match) -> Backend {
        FixtureServer.state = state
        let name = "dl.fixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = DeviceSettings(defaults: defaults)
        settings.setThemeMode(theme)
        settings.setLeaves(false)
        let config = AppConfig(environment: .staging, apiBaseURL: FixtureServer.baseURL, version: "0.1.0", build: "1")
        return Backend(
            config: config,
            settings: settings,
            cookies: CookieStore(service: name, inMemory: true),
            biometrics: BiometricVault(service: name),
            protocolClasses: [FixtureServer.self]
        )
    }
}
