import DLData
import DLI18n
import DLNetwork
import Foundation

// Home Screen and Lock Screen widgets (iOS design §6, Selfies DS12, doc "Delululand — iPad Layout"
// WG1–WG14): the board, today's selfies, and both clocks with moods. The extension loads Home with
// the app's session from the shared keychain group (WG2), like the Notification Service Extension.

/// A citizen as the clocks widget shows them.
public struct WidgetCitizen: Codable, Equatable, Sendable {
    public var name: String
    public var zone: String
    public var mood: String?

    public init(name: String, zone: String, mood: String?) {
        self.name = name
        self.zone = zone
        self.mood = mood
    }

    public var city: String { DLTime.city(of: zone) }
}

/// One frame of the selfie board.
public enum SelfieSlot: Codable, Equatable, Sendable {
    /// The picture (JPEG bytes, already scaled down).
    case photo(Data, takenAt: Date, expiresAt: Date)
    /// The friend's selfie while mine is missing (Q2): only the 24 px preview, shown blurred (WG6).
    case locked(blur: Data?, takenAt: Date, expiresAt: Date)
    case none

    public var expiresAt: Date? {
        switch self {
        case let .photo(_, _, at), let .locked(_, _, at): at
        case .none: nil
        }
    }

    public var takenAt: Date? {
        switch self {
        case let .photo(_, at, _), let .locked(_, at, _): at
        case .none: nil
        }
    }

    public var isEmpty: Bool { self == .none }
}

/// The board as the widget shows it (WG12): the latest doodle, who drew it and when, NEW.
public struct WidgetBoard: Codable, Equatable, Sendable {
    public var image: Data?
    public var mine: Bool
    public var authorName: String
    public var createdAt: Date
    public var isNew: Bool

    public init(image: Data?, mine: Bool, authorName: String, createdAt: Date, isNew: Bool) {
        self.image = image
        self.mine = mine
        self.authorName = authorName
        self.createdAt = createdAt
        self.isNew = isNew
    }
}

/// Everything the widgets show, at one moment.
public struct WidgetData: Codable, Equatable, Sendable {
    public var signedIn: Bool
    /// The universe's name (Universe C48), "Delulutopia" signed out.
    public var brand: String
    public var lang: String
    public var me: WidgetCitizen?
    public var friend: WidgetCitizen?
    /// The friend's name for sentences ("your friend" while alone).
    public var friendName: String
    public var board: WidgetBoard?
    /// False before the selfies story (API before V32): the Selfies widget says nothing is there.
    public var selfiesOn: Bool
    public var mine: SelfieSlot
    public var theirs: SelfieSlot

    public init(
        signedIn: Bool, brand: String, lang: String, me: WidgetCitizen?, friend: WidgetCitizen?, friendName: String,
        board: WidgetBoard?, selfiesOn: Bool, mine: SelfieSlot, theirs: SelfieSlot
    ) {
        self.signedIn = signedIn
        self.brand = brand
        self.lang = lang
        self.me = me
        self.friend = friend
        self.friendName = friendName
        self.board = board
        self.selfiesOn = selfiesOn
        self.mine = mine
        self.theirs = theirs
    }

    /// WG7: no session on this device (never signed in, logged out, data deleted).
    public static let signedOut = WidgetData(
        signedIn: false, brand: "Delulutopia", lang: Lang.en.rawValue, me: nil, friend: nil, friendName: "",
        board: nil, selfiesOn: false, mine: .none, theirs: .none
    )

    /// The widget gallery's preview (the design's sample data: Emin in Warsaw, Leyla in Tehran).
    public static func sample(now: Date = Date()) -> WidgetData {
        WidgetData(
            signedIn: true, brand: "Delulutopia", lang: I18n.shared.lang.rawValue,
            me: WidgetCitizen(name: "Emin", zone: "Europe/Warsaw", mood: Moods.text("HAPPY")),
            friend: WidgetCitizen(name: "Leyla", zone: "Asia/Tehran", mood: Moods.text("CALM")),
            friendName: "Leyla",
            board: WidgetBoard(image: nil, mine: false, authorName: "Leyla", createdAt: now.addingTimeInterval(-7200), isNew: true),
            selfiesOn: true, mine: .none, theirs: .none
        )
    }

    /// The selfie board's state, for the views and the tests.
    public var selfies: SelfiesState {
        guard signedIn else { return .signedOut }
        switch (mine, theirs) {
        case (.none, .none): return .none
        case (.none, .locked), (.none, .photo): return .theirsOnly
        case (_, .none): return .mineOnly
        default: return .both
        }
    }

    /// This moment's view of the data: selfies past their expiry are gone (DS7).
    public func at(_ date: Date) -> WidgetData {
        var copy = self
        if let at = mine.expiresAt, at <= date { copy.mine = .none }
        if let at = theirs.expiresAt, at <= date { copy.theirs = .none }
        return copy
    }
}

/// The Selfies widget's states (Selfies canvas W-States).
public enum SelfiesState: Equatable, Sendable {
    case both
    /// The friend's is up, mine is missing: theirs stays locked (Q2) with "Add yours to see it".
    case theirsOnly
    case mineOnly
    case none
    case signedOut
}

/// When the widgets change by themselves (WG3): every 30 min, and at each selfie's expiry.
public enum WidgetTimeline {
    public static let refresh: TimeInterval = 30 * 60

    /// The entry dates from `now`: now, then each expiry before the next refresh.
    public static func dates(_ data: WidgetData, now: Date) -> [Date] {
        let end = now.addingTimeInterval(refresh)
        let expiries = [data.mine.expiresAt, data.theirs.expiresAt]
            .compactMap { $0 }
            .filter { $0 > now && $0 < end }
            .sorted()
        return [now] + expiries
    }

    /// The age line the board and selfies use ("2 h ago"), like Home's.
    public static func age(_ since: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(since)))
        if s < 60 { return t("common.age.justNow") }
        let m = s / 60
        if m < 60 { return t("common.age.min", ["n": m]) }
        let h = m / 60
        if h < 24 { return t("common.age.h", ["n": h]) }
        return t("common.age.d", ["n": h / 24])
    }

    /// "Leyla drew this · 2 h ago" (the board's own byline keys).
    public static func byline(_ board: WidgetBoard, friend: String, now: Date) -> String {
        let key = board.mine ? "board.byline.meDrew" : "board.byline.friendDrew"
        let name = board.mine ? t("board.you") : board.authorName
        return t(key, ["friend": friend, "age": age(board.createdAt, now: now)])
            .replacingOccurrences(of: "{name}", with: name)
    }
}

/// The links a widget tap opens (WG4), read by the app's `AppLink(url:)`.
public enum WidgetLink {
    /// The app's URL scheme (`delulutopia`, `delulutopia-tst` on staging), from the Info.plist.
    public static var scheme: String {
        (Bundle.main.object(forInfoDictionaryKey: "DLURLScheme") as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 } ?? "delulutopia"
    }

    public static var home: URL { URL(string: "\(scheme)://home")! }
    public static var board: URL { URL(string: "\(scheme)://home/board")! }
    public static var selfies: URL { URL(string: "\(scheme)://home/selfies")! }
    public static var selfieCamera: URL { URL(string: "\(scheme)://home/selfies/camera")! }
}

/// Builds `WidgetData` from Home and the images the extension downloaded.
public enum WidgetMapping {
    public static func make(home: Home, boardImage: Data?, mineImage: Data?, theirsImage: Data?) -> WidgetData {
        func citizen(_ c: Citizen) -> WidgetCitizen {
            WidgetCitizen(name: c.nickname, zone: c.timezone ?? "UTC", mood: Moods.text(c.mood, emoji: c.moodEmoji, label: c.moodLabel))
        }
        func slot(_ s: Selfie?, mine: Bool, image: Data?) -> SelfieSlot {
            guard let s, let taken = DLTime.date(s.createdAt), let gone = DLTime.date(s.expiresAt) else { return .none }
            let mineMissing = home.selfies?.mine == nil
            if !mine, s.locked || s.url == nil || mineMissing {
                return .locked(blur: blurBytes(s.blurPreview), takenAt: taken, expiresAt: gone)
            }
            guard let image else { return .locked(blur: blurBytes(s.blurPreview), takenAt: taken, expiresAt: gone) }
            return .photo(image, takenAt: taken, expiresAt: gone)
        }
        let board = home.board.flatMap { b -> WidgetBoard? in
            guard let at = DLTime.date(b.createdAt) else { return nil }
            let mine = b.authorId == home.me.id
            return WidgetBoard(image: boardImage, mine: mine, authorName: mine ? home.me.nickname : home.friendName, createdAt: at, isNew: home.boardNew)
        }
        return WidgetData(
            signedIn: true,
            brand: home.universe.name,
            lang: home.me.language ?? I18n.shared.lang.rawValue,
            me: citizen(home.me),
            friend: home.friend.map(citizen),
            friendName: home.friendName,
            board: board,
            selfiesOn: home.selfies != nil,
            mine: slot(home.selfies?.mine, mine: true, image: mineImage),
            theirs: slot(home.selfies?.theirs, mine: false, image: theirsImage)
        )
    }

    /// The `data:image/jpeg;base64,…` preview's bytes.
    public static func blurBytes(_ uri: String?) -> Data? {
        guard let uri, let comma = uri.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...]))
    }
}
