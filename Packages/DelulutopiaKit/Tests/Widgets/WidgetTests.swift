import DLData
import DLI18n
import DLNetwork
@testable import DLWidgets
import Foundation
import Testing

/// The widgets' data (doc "Delululand — iPad Layout" WG2–WG7, WG12, WG13).
@Suite("Widgets")
struct WidgetTests {
    private let now = DLTime.date("2026-11-21T12:00:00Z")!

    private func iso(_ minutes: Double) -> String { DLTime.iso(now.addingTimeInterval(minutes * 60)) }

    private func home(mine: [String: Any]? = nil, theirs: [String: Any]? = nil, board: Bool = true, selfies: Bool = true, friend: Bool = true) -> Home {
        var json: [String: Any] = [
            "serverNow": iso(0),
            "me": ["id": "1", "nickname": "Emin", "timezone": "Europe/Warsaw", "mood": "HAPPY", "language": "en"],
            "universe": ["id": "u1", "name": "Delulutopia"],
            "boardNew": true,
        ]
        if friend { json["friend"] = ["id": "2", "nickname": "Leyla", "timezone": "Asia/Tehran", "mood": "CALM"] }
        if board { json["board"] = ["version": 3, "authorId": "2", "createdAt": iso(-120), "url": "/api/board/image?u=u1"] }
        if selfies {
            var s: [String: Any] = ["ttlHours": 24]
            if let mine { s["mine"] = mine }
            if let theirs { s["theirs"] = theirs }
            json["selfies"] = s
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Home.self, from: data)
    }

    private func selfie(_ id: String, author: String, takenMin: Double, goneMin: Double, url: String? = "/api/selfies/x/image", locked: Bool = false) -> [String: Any] {
        var s: [String: Any] = ["id": id, "authorId": author, "createdAt": iso(takenMin), "expiresAt": iso(goneMin), "locked": locked]
        if let url { s["url"] = url }
        if locked { s["blurPreview"] = "data:image/jpeg;base64,AAEC" }
        return s
    }

    @Test("Clocks: names, zones, cities and moods from Home")
    func clocks() {
        let data = WidgetMapping.make(home: home(), boardImage: nil, mineImage: nil, theirsImage: nil)
        #expect(data.signedIn)
        #expect(data.brand == "Delulutopia")
        #expect(data.me?.name == "Emin")
        #expect(data.me?.city == "Warsaw")
        #expect(data.friend?.zone == "Asia/Tehran")
        #expect(data.me?.mood == Moods.text("HAPPY"))
        #expect(data.friend?.mood == Moods.text("CALM"))
    }

    @Test("Board: the friend's doodle, NEW, the byline (WG12)")
    func board() {
        let data = WidgetMapping.make(home: home(), boardImage: Data([1]), mineImage: nil, theirsImage: nil)
        #expect(data.board?.mine == false)
        #expect(data.board?.authorName == "Leyla")
        #expect(data.board?.isNew == true)
        #expect(data.board?.image == Data([1]))
        I18n.shared.set(.en)
        let line = WidgetTimeline.byline(data.board!, friend: data.friendName, now: now)
        #expect(line.contains("Leyla"))
        #expect(line.contains("2 h ago"))
        #expect(!line.contains("{name}"))
    }

    @Test("Board: empty when nothing was drawn")
    func boardEmpty() {
        #expect(WidgetMapping.make(home: home(board: false), boardImage: nil, mineImage: nil, theirsImage: nil).board == nil)
    }

    @Test("Selfies: none, mine only, theirs locked, both")
    func selfieStates() {
        let none = WidgetMapping.make(home: home(), boardImage: nil, mineImage: nil, theirsImage: nil)
        #expect(none.selfies == .none)

        let mineOnly = WidgetMapping.make(home: home(mine: selfie("m", author: "1", takenMin: -60, goneMin: 600)), boardImage: nil, mineImage: Data([7]), theirsImage: nil)
        #expect(mineOnly.selfies == .mineOnly)

        // WG6: the friend's selfie while mine is missing is never a photo, only the blurred preview.
        let locked = WidgetMapping.make(
            home: home(theirs: selfie("t", author: "2", takenMin: -30, goneMin: 600, url: nil, locked: true)),
            boardImage: nil, mineImage: nil, theirsImage: Data([9])
        )
        #expect(locked.selfies == .theirsOnly)
        guard case let .locked(blur, _, _) = locked.theirs else {
            Issue.record("expected locked")
            return
        }
        #expect(blur == Data([0, 1, 2]))

        let both = WidgetMapping.make(
            home: home(mine: selfie("m", author: "1", takenMin: -60, goneMin: 600), theirs: selfie("t", author: "2", takenMin: -30, goneMin: 600)),
            boardImage: nil, mineImage: Data([7]), theirsImage: Data([9])
        )
        #expect(both.selfies == .both)
        #expect(both.theirs == .photo(Data([9]), takenAt: now.addingTimeInterval(-1800), expiresAt: now.addingTimeInterval(36000)))
    }

    @Test("Selfies: off before the selfies story")
    func selfiesOff() {
        let data = WidgetMapping.make(home: home(selfies: false), boardImage: nil, mineImage: nil, theirsImage: nil)
        #expect(!data.selfiesOn)
        #expect(data.selfies == .none)
    }

    @Test("Signed out (WG7)")
    func signedOut() {
        #expect(WidgetData.signedOut.selfies == .signedOut)
        #expect(!WidgetData.signedOut.signedIn)
    }

    @Test("Timeline: an entry now and one at each expiry before the next reload (WG3, DS7)")
    func timeline() {
        let data = WidgetMapping.make(
            home: home(mine: selfie("m", author: "1", takenMin: -600, goneMin: 10), theirs: selfie("t", author: "2", takenMin: -30, goneMin: 600)),
            boardImage: nil, mineImage: Data([7]), theirsImage: Data([9])
        )
        let dates = WidgetTimeline.dates(data, now: now)
        #expect(dates == [now, now.addingTimeInterval(600)])
        let later = data.at(now.addingTimeInterval(600))
        #expect(later.mine == .none)
        #expect(later.selfies == .theirsOnly)
        #expect(data.at(now).selfies == .both)
    }

    @Test("Ages read like Home's")
    func ages() {
        I18n.shared.set(.en)
        #expect(WidgetTimeline.age(now, now: now) == "just now")
        #expect(WidgetTimeline.age(now.addingTimeInterval(-25 * 60), now: now) == "25 min ago")
        #expect(WidgetTimeline.age(now.addingTimeInterval(-3 * 86400), now: now) == "3 d ago")
    }

    @Test("The data survives the extension's cache")
    func codable() throws {
        let data = WidgetMapping.make(
            home: home(mine: selfie("m", author: "1", takenMin: -60, goneMin: 600), theirs: selfie("t", author: "2", takenMin: -30, goneMin: 600, url: nil, locked: true)),
            boardImage: Data([1]), mineImage: Data([7]), theirsImage: nil
        )
        let back = try JSONDecoder().decode(WidgetData.self, from: JSONEncoder().encode(data))
        #expect(back == data)
    }

    @Test("Widget links read back as Home intents (WG4)")
    func links() {
        #expect(AppLink(url: URL(string: "delulutopia://home/board")!) == .board)
        #expect(AppLink(url: URL(string: "delulutopia-tst://home/selfies")!) == .selfies)
        #expect(AppLink(url: URL(string: "delulutopia://home/selfies/camera")!) == .selfieCamera)
        #expect(AppLink(url: URL(string: "delulutopia://home")!) == .home)
        #expect(AppLink(url: URL(string: "delulutopia://letters/abc")!) == .letter("abc"))
        #expect(AppLink.board.homeIntent == .board)
        #expect(AppLink.letters.homeIntent == nil)
    }
}
