import DLI18n
import Foundation

// Response shapes of Technical Design §5.2, one-to-one with delululand-web `src/api/types.ts` and the
// Android `Models.kt`. Instants are ISO-8601 UTC strings (`DLTime` parses them).

/// A public id (doc "Delululand — Public IDs"): a random UUID the server gives every letter,
/// discussion, comment, email thread, email, user and universe. Opaque: compared, never parsed or ordered.
public typealias PublicID = String

// MARK: - Attachments and stamps

public struct Att: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// photo | audio | video | doodle; `video` only on emails, its `thumbUrl` is the poster.
    public var kind: String
    public var url: String
    public var thumbUrl: String?
    public var width: Int?
    public var height: Int?
    public var durationMs: Int?
    @Default<Zero> public var position: Int
    /// Its files are gone (doc "Delululand — Attachment Retention" AR7): the URLs answer 410; show a placeholder.
    @Default<False> public var expired: Bool

    public init(
        id: String,
        kind: String,
        url: String,
        thumbUrl: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil,
        position: Int = 0,
        expired: Bool = false
    ) {
        self.expired = expired
        self.id = id
        self.kind = kind
        self.url = url
        self.thumbUrl = thumbUrl
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.position = position
    }
}

public struct StampMark: Codable, Sendable, Hashable {
    public var slug: String
    public var name: String
    public var imageUrl: String

    public init(slug: String, name: String, imageUrl: String) {
        self.slug = slug
        self.name = name
        self.imageUrl = imageUrl
    }
}

public struct StampView: Codable, Sendable, Hashable, Identifiable {
    public var slug: String
    public var name: String
    public var imageUrl: String
    @Default<EmptyList<String>> public var keywords: [String]
    public var theme: String
    @Default<Zero> public var sort: Int

    public var id: String { slug }
    public var mark: StampMark { StampMark(slug: slug, name: name, imageUrl: imageUrl) }
}

public struct StampTheme: Codable, Sendable, Hashable, Identifiable {
    public var slug: String
    public var name: String
    @Default<Zero> public var sort: Int

    public var id: String { slug }
}

public struct StampCatalogue: Codable, Sendable, Hashable {
    public var themes: [StampTheme]
    public var stamps: [StampView]
    @Default<EmptyList<String>> public var recent: [String]
}

// MARK: - Letters

public struct LetterMedia: Codable, Sendable, Hashable {
    @Default<Zero> public var photos: Int
    @Default<Zero> public var audios: Int
    @Default<Zero> public var doodles: Int
}

/// A letter list row; `state` is IN_REACH | IN_TRANSIT | DELIVERED | READ.
public struct LetterRow: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    /// to | from
    public var direction: String
    public var state: String
    public var sentAt: String
    public var windowEndsAt: String
    public var arrivesAt: String
    public var readAt: String?
    public var firstLine: String?
    public var media: LetterMedia?
    public var moodAtSend: String?
    public var moodEmoji: String?
    public var moodLabel: String?
    public var stamp: StampMark?
    public var replyToId: PublicID?

    public var isMine: Bool { direction == "to" }
}

public struct ReplyRef: Codable, Sendable, Hashable {
    public var id: PublicID
    public var direction: String
    public var sentAt: String
    public var firstLine: String?
    public var media: LetterMedia?
}

public struct LetterFull: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var direction: String
    public var state: String
    public var sentAt: String
    public var windowEndsAt: String
    public var arrivesAt: String
    public var readAt: String?
    public var firstLine: String?
    public var media: LetterMedia?
    public var moodAtSend: String?
    public var moodEmoji: String?
    public var moodLabel: String?
    public var stamp: StampMark?
    public var replyToId: PublicID?
    public var body: Doc?
    @Default<EmptyList<Att>> public var attachments: [Att]
    @Default<False> public var canEdit: Bool
    @Default<False> public var canCancel: Bool
    public var editAttachments: [Att]?
    public var replyTo: ReplyRef?

    public var isMine: Bool { direction == "to" }
    public var doc: Doc { body ?? .empty }

    public var row: LetterRow {
        LetterRow(
            id: id, direction: direction, state: state, sentAt: sentAt, windowEndsAt: windowEndsAt,
            arrivesAt: arrivesAt, readAt: readAt, firstLine: firstLine, media: media, moodAtSend: moodAtSend,
            moodEmoji: moodEmoji, moodLabel: moodLabel, stamp: stamp, replyToId: replyToId
        )
    }
}

public struct LetterPage: Codable, Sendable, Hashable {
    public var items: [LetterRow]
    public var nextCursor: String?
}

public struct Draft: Codable, Sendable, Hashable {
    public var body: Doc?
    @Default<EmptyList<Att>> public var attachments: [Att]
    public var pinnedLetterId: PublicID?
    public var stamp: StampMark?
    @Default<Zero> public var version: Int
    public var savedAt: String?

    public var doc: Doc { body ?? .empty }
}

public struct Saved: Codable, Sendable, Hashable {
    public var version: Int
    public var savedAt: String

    public init(version: Int, savedAt: String) {
        self.version = version
        self.savedAt = savedAt
    }
}

public struct Sent: Codable, Sendable, Hashable {
    public var id: PublicID
    public var sentAt: String
    public var windowEndsAt: String
    public var arrivesAt: String
}

public struct DraftVersion: Codable, Sendable, Hashable {
    public var draftVersion: Int
}

// MARK: - Home

/// A citizen as Home sees them.
public struct Citizen: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var nickname: String
    public var avatarUrl: String?
    public var mood: String?
    public var moodSetAt: String?
    public var moodEmoji: String?
    public var moodLabel: String?
    public var timezone: String?
    public var firstName: String?
    public var lastName: String?
    /// L8: `en`, `az` or `fa`; absent from servers before the language feature.
    public var language: String?
    @Default<True> public var draftEmpty: Bool
    @Default<True> public var discussionDraftEmpty: Bool
}

public struct Mood: Codable, Sendable, Hashable, Identifiable {
    public var key: String
    public var emoji: String
    public var label: String
    @Default<False> public var custom: Bool

    public var id: String { key }

    public init(key: String, emoji: String, label: String, custom: Bool = false) {
        self.key = key
        self.emoji = emoji
        self.label = label
        self.custom = custom
    }
}

public struct MoodCatalogue: Codable, Sendable, Hashable {
    public var limit: Int?
    public var moods: [Mood]
}

public struct NotifyPrefs: Codable, Sendable, Hashable {
    @Default<False> public var paused: Bool
    @Default<EmptyList<String>> public var enabled: [String]
}

public struct UniverseInfo: Codable, Sendable, Hashable {
    public var id: PublicID
    public var name: String
    @Default<False> public var isCreator: Bool
    @Default<False> public var waiting: Bool
}

public struct Home: Codable, Sendable, Hashable {
    public var serverNow: String
    public var me: Citizen
    public var friend: Citizen?
    @Default<EmptyList<LetterRow>> public var from: [LetterRow]
    @Default<EmptyList<LetterRow>> public var to: [LetterRow]
    @Default<Zero> public var unreadCount: Int
    @Default<Zero> public var discussionsUnseen: Int
    @Default<EmptyList<DiscussionArrival>> public var newDiscussions: [DiscussionArrival]
    @Default<Zero> public var emailsUnread: Int
    @Default<Zero> public var emailsReacted: Int
    @Default<EmptyList<EmailArrival>> public var newEmails: [EmailArrival]
    public var emailCredits: EmailCredits?
    public var board: Board?
    @Default<False> public var boardNew: Bool
    public var notifyPrefs: NotifyPrefs?
    public var universe: UniverseInfo
    /// Subscription Tiers: nil from an API before V24; nothing is limited on screen then.
    public var plan: Plan?

    /// The other citizen's name for sentences, or "your friend" while the creator is alone (Universe U8).
    public var friendName: String { friend?.nickname ?? t("settings.yourFriend") }
}

public struct HomeCounts: Codable, Sendable, Hashable {
    @Default<Zero> public var unreadCount: Int
    @Default<Zero> public var discussionsUnseen: Int
    @Default<Zero> public var emailsUnread: Int
    @Default<Zero> public var emailsReacted: Int
    @Default<False> public var boardNew: Bool
}

public struct MoodChange: Codable, Sendable, Hashable {
    public var mood: String
    public var moodSetAt: String
}

// MARK: - Board (doc "Delululand — Board" §3)

public struct Board: Codable, Sendable, Hashable {
    public var version: Int
    public var authorId: PublicID
    public var createdAt: String
    public var url: String
    public var reaction: String?
    public var editedFrom: PublicID?
    public var comment: BoardComment?
}

public struct BoardComment: Codable, Sendable, Hashable {
    public var text: String
    public var createdAt: String
}

// MARK: - Reactions (doc "Delululand — Reactions")

public struct Reaction: Codable, Sendable, Hashable, Identifiable {
    public var emoji: String
    public var userIds: [PublicID]

    public var id: String { emoji }

    public init(emoji: String, userIds: [PublicID]) {
        self.emoji = emoji
        self.userIds = userIds
    }
}

public struct Reactions: Codable, Sendable, Hashable {
    public var reactions: [Reaction]
}

public struct ReactionNotice: Codable, Sendable, Hashable {
    public var userId: PublicID
    public var emoji: String
    /// discussion | comment | email
    public var target: String
    @Default<False> public var onMine: Bool
    public var text: String?
    /// video | photo | audio
    public var media: String?
    public var at: String
}

// MARK: - Discussions (doc "Delululand — Discussions" §5)

public struct DiscussionArrival: Codable, Sendable, Hashable {
    public var id: PublicID
    public var title: String
    public var arrivesAt: String
}

public struct DMedia: Codable, Sendable, Hashable {
    @Default<Zero> public var photos: Int
    @Default<Zero> public var audios: Int
}

public struct DRow: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var authorId: PublicID
    public var mine: Bool
    public var color: String?
    /// IN_REACH | IN_TRANSIT | ARRIVED
    public var state: String
    public var postedAt: String
    public var windowEndsAt: String
    public var arrivesAt: String
    public var title: String?
    public var firstLine: String?
    public var media: DMedia?
    public var commentCount: Int?
    public var lastCommentAt: String?
    @Default<False> public var isNew: Bool
    @Default<Zero> public var unseenComments: Int
    @Default<Zero> public var unseenReactions: Int
    public var lastReaction: ReactionNotice?
    public var editedAt: String?
    public var activityAt: String?
    public var archivedAt: String?
    public var archivedBy: PublicID?
}

public struct DComment: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var authorId: PublicID
    public var text: String
    public var createdAt: String
    public var editedAt: String?
    @Default<EmptyList<Reaction>> public var reactions: [Reaction]
}

public struct DComments: Codable, Sendable, Hashable {
    public var items: [DComment]
    public var olderCursor: String?

    public init(items: [DComment] = [], olderCursor: String? = nil) {
        self.items = items
        self.olderCursor = olderCursor
    }
}

public struct DFull: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var authorId: PublicID
    public var mine: Bool
    public var color: String?
    public var state: String
    public var postedAt: String
    public var windowEndsAt: String
    public var arrivesAt: String
    @Default<EmptyString> public var title: String
    public var firstLine: String?
    public var media: DMedia?
    public var commentCount: Int?
    public var lastCommentAt: String?
    @Default<False> public var isNew: Bool
    @Default<Zero> public var unseenComments: Int
    public var editedAt: String?
    public var activityAt: String?
    public var archivedAt: String?
    public var archivedBy: PublicID?
    public var body: Doc?
    @Default<EmptyList<Att>> public var attachments: [Att]
    @Default<False> public var canCancel: Bool
    public var comments: DComments?
    @Default<EmptyList<Reaction>> public var reactions: [Reaction]
    @Default<False> public var canEdit: Bool
    @Default<False> public var canDelete: Bool
    @Default<False> public var canArchive: Bool
    @Default<False> public var canUnarchive: Bool

    public var doc: Doc { body ?? .empty }
}

public struct DPage: Codable, Sendable, Hashable {
    public var items: [DRow]
    public var nextCursor: String?
    @Default<Zero> public var archivedCount: Int
}

public struct DDraft: Codable, Sendable, Hashable {
    @Default<EmptyString> public var title: String
    public var color: String?
    public var body: Doc?
    @Default<EmptyList<Att>> public var attachments: [Att]
    @Default<Zero> public var version: Int
    public var savedAt: String?

    public var doc: Doc { body ?? .empty }
}

public struct DPosted: Codable, Sendable, Hashable {
    public var id: PublicID
    public var postedAt: String
    public var windowEndsAt: String
    public var arrivesAt: String
}

// MARK: - Emails (doc "Delululand — Emails" §4)

public struct EmailArrival: Codable, Sendable, Hashable {
    public var id: PublicID
    public var threadId: PublicID
    public var subject: String
    public var sentAt: String
}

public struct EmailCredits: Codable, Sendable, Hashable {
    public var limit: Int
    public var used: Int
    public var left: Int
    public var renewsAt: String
}

public struct ThreadMedia: Codable, Sendable, Hashable {
    @Default<Zero> public var photos: Int
    @Default<Zero> public var audios: Int
    @Default<Zero> public var videos: Int

    public init(photos: Int = 0, audios: Int = 0, videos: Int = 0) {
        self.photos = photos
        self.audios = audios
        self.videos = videos
    }
}

public struct ThreadRow: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var subject: String
    public var startedBy: PublicID
    public var createdAt: String
    public var lastEmailAt: String
    public var lastSenderId: PublicID?
    public var lastText: String?
    public var lastMedia: ThreadMedia?
    @Default<Zero> public var emailCount: Int
    @Default<Zero> public var unread: Int
    @Default<Zero> public var unseenReactions: Int
    public var lastReaction: ReactionNotice?
    /// The newest email answers another (doc "Delululand — Email Replies" RE13: the ↩ prefix).
    @Default<False> public var lastIsReply: Bool
}

/// The quote of a reply (Email Replies RE9, RE11): the answered email's first 120 characters on one
/// line (nil without text), its media counts and the first photo's thumbnail or the video's poster.
public struct EmailQuote: Codable, Sendable, Hashable {
    public var id: PublicID
    public var senderId: PublicID
    public var text: String?
    public var media: ThreadMedia?
    public var thumbUrl: String?
    /// The photo or video it would show has expired (Attachment Retention AR9): the crossed-out icon.
    @Default<False> public var thumbExpired: Bool
    public var sentAt: String

    public init(id: PublicID, senderId: PublicID, text: String?, media: ThreadMedia?, thumbUrl: String?, thumbExpired: Bool = false, sentAt: String) {
        self.thumbExpired = thumbExpired
        self.id = id
        self.senderId = senderId
        self.text = text
        self.media = media
        self.thumbUrl = thumbUrl
        self.sentAt = sentAt
    }
}

public struct Email: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var threadId: PublicID
    public var senderId: PublicID
    @Default<EmptyString> public var text: String
    public var sentAt: String
    public var readAt: String?
    @Default<EmptyList<Att>> public var attachments: [Att]
    @Default<EmptyList<Reaction>> public var reactions: [Reaction]
    /// The email this one answers (RE11); nil for a plain email.
    public var replyTo: EmailQuote?
}

public struct EmailList: Codable, Sendable, Hashable {
    public var items: [Email]
    public var olderCursor: String?
}

public struct ThreadPage: Codable, Sendable, Hashable {
    public var items: [ThreadRow]
    public var nextCursor: String?
}

public struct ThreadFull: Codable, Sendable, Hashable {
    public var thread: ThreadRow
    public var emails: EmailList
}

public struct EmailSent: Codable, Sendable, Hashable {
    public var thread: ThreadRow
    public var email: Email
    public var credits: EmailCredits
}

public struct EmailDraft: Codable, Sendable, Hashable {
    @Default<EmptyString> public var subject: String
    @Default<EmptyString> public var text: String
    @Default<EmptyList<Att>> public var attachments: [Att]
    @Default<Zero> public var version: Int
    public var savedAt: String?
    /// A thread draft's reply target (RE10).
    public var replyTo: EmailQuote?
}

// MARK: - Profile and settings (doc "Delululand — Menu, Profile & Settings" §6)

public struct Profile: Codable, Sendable, Hashable {
    public var id: PublicID
    public var username: String
    public var firstName: String?
    public var lastName: String?
    public var timezone: String
    public var avatarUrl: String?
}

public struct NotifyEvent: Codable, Sendable, Hashable, Identifiable {
    public var key: String
    public var enabled: Bool
    @Default<True> public var defaultOn: Bool

    public var id: String { key }
}

public struct NotifySection: Codable, Sendable, Hashable, Identifiable {
    public var key: String
    public var enabled: Bool
    public var events: [NotifyEvent]

    public var id: String { key }
}

public struct NotifySettings: Codable, Sendable, Hashable {
    public var paused: Bool
    public var sections: [NotifySection]
}

public struct UniverseCreator: Codable, Sendable, Hashable {
    public var id: PublicID
    public var username: String
}

public struct UniverseView: Codable, Sendable, Hashable {
    public var id: PublicID
    public var name: String
    public var welcome: String
    public var creator: UniverseCreator?
    @Default<False> public var isCreator: Bool
    public var codeRotatedAt: String?
    public var tier: String?
    public var limits: PlanLimits?
}

// MARK: - Subscription tiers (doc "Delululand — Subscription Tiers" §5)

public struct PlanLimits: Codable, Sendable, Hashable {
    public var emailsDaily: Int
    public var photosPerMessage: Int
    public var photosDaily: Int
    public var videoSeconds: Int
    public var videoMb: Int
    public var videosDaily: Int
    /// nil is unlimited (Premium, ST1).
    public var boardDoodlesDaily: Int?

    public init(emailsDaily: Int, photosPerMessage: Int, photosDaily: Int, videoSeconds: Int, videoMb: Int, videosDaily: Int, boardDoodlesDaily: Int?) {
        self.emailsDaily = emailsDaily
        self.photosPerMessage = photosPerMessage
        self.photosDaily = photosDaily
        self.videoSeconds = videoSeconds
        self.videoMb = videoMb
        self.videosDaily = videosDaily
        self.boardDoodlesDaily = boardDoodlesDaily
    }
}

public struct PlanLeft: Codable, Sendable, Hashable {
    public var emails: Int
    public var photos: Int
    public var videos: Int
    public var boardDoodles: Int?

    public init(emails: Int, photos: Int, videos: Int, boardDoodles: Int?) {
        self.emails = emails
        self.photos = photos
        self.videos = videos
        self.boardDoodles = boardDoodles
    }
}

public struct Plan: Codable, Sendable, Hashable {
    public var tier: String
    public var limits: PlanLimits
    public var left: PlanLeft
    public var renewsAt: String

    public init(tier: String, limits: PlanLimits, left: PlanLeft, renewsAt: String) {
        self.tier = tier
        self.limits = limits
        self.left = left
        self.renewsAt = renewsAt
    }

    public var premium: Bool { tier == "premium" }
}

public struct KeyCode: Codable, Sendable, Hashable {
    public var code: String
}

/// `GET /api/config`: timings of this server (the TEST banner reads them).
public struct ServerSettings: Codable, Sendable, Hashable {
    public var delay: String
    public var window: String
    public var discussionDelay: String?
    @Default<Zero> public var emailDailyCredits: Int
    public var env: String
    @Default<False> public var testTiming: Bool
    public var serverNow: String
    /// Attachment Retention AR14: days the files of letters / others are kept; absent from an older API.
    public var retention: RetentionDays?
}

public struct RetentionDays: Codable, Sendable, Hashable {
    public var letterDays: Int
    public var otherDays: Int
}

// MARK: - Entry, auth and universe (Android `Account.kt`)

public struct Entered: Codable, Sendable, Hashable {
    public var name: String
    public var welcome: String
}

public struct UserCard: Codable, Sendable, Hashable, Identifiable {
    public var id: PublicID
    public var nickname: String
    public var avatarUrl: String?
    public var hasPin: Bool
}

/// UV-4: the universe behind the entry pass.
public struct EntryView: Codable, Sendable, Hashable {
    public var name: String
    public var welcome: String
    public var canJoin: Bool
    public var users: [UserCard]
}

public struct CreatedUniverse: Codable, Sendable, Hashable {
    public struct Ref: Codable, Sendable, Hashable {
        public var id: PublicID
        public var name: String
    }

    public var code: String
    public var universe: Ref
}

/// The parts of `GET /api/home` the session needs.
public struct HomeSession: Codable, Sendable, Hashable {
    public var me: Person
    public var friend: Person?
    public var universe: UniverseInfo
}

public struct Person: Codable, Sendable, Hashable {
    public var id: PublicID
    public var nickname: String
    public var avatarUrl: String?
    public var timezone: String?

    public init(id: PublicID, nickname: String, avatarUrl: String? = nil, timezone: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.timezone = timezone
    }
}
