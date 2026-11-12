import Foundation

// Request bodies (Android `Requests.kt`, `Account.kt`). Field names are the API's.

struct CodeBody: Encodable { let code: String }
struct LoginBody: Encodable { let userId: Int; let pin: String }
struct InviteBody: Encodable { let invite: String }
struct VersionBody: Encodable { let version: Int }
struct ReactionVersionBody: Encodable { let version: Int; let reaction: String }
struct BoardCommentBody: Encodable { let version: Int; let text: String }
struct TextBody: Encodable { let text: String }
struct EmojiBody: Encodable { let emoji: String }
struct MoodBody: Encodable { let mood: String }
struct MoodEditBody: Encodable { let emoji: String; let label: String }
struct DraftVersionBody: Encodable { let draftVersion: Int }
struct BodyOnly: Encodable { let body: Doc }
struct ChangePinBody: Encodable { let currentPin: String; let newPin: String }
struct UniverseUpdate: Encodable { let name: String; let welcome: String }

public struct CreateUniverseRequest: Encodable, Sendable {
    public let invite: String
    public let name: String
    public let welcome: String
    public let username: String
    public let timezone: String
    public let pin: String

    public init(invite: String, name: String, welcome: String, username: String, timezone: String, pin: String) {
        self.invite = invite
        self.name = name
        self.welcome = welcome
        self.username = username
        self.timezone = timezone
        self.pin = pin
    }
}

struct JoinBody: Encodable { let username: String; let timezone: String; let pin: String }

/// `pinnedLetterId` and `stampSlug` are sent as null to clear them.
struct SaveDraftBody: Encodable {
    let body: Doc
    let pinnedLetterId: Int?
    let stampSlug: String?
    let version: Int

    enum CodingKeys: String, CodingKey { case body, pinnedLetterId, stampSlug, version }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(body, forKey: .body)
        try c.encode(pinnedLetterId, forKey: .pinnedLetterId)
        try c.encode(stampSlug, forKey: .stampSlug)
        try c.encode(version, forKey: .version)
    }
}

struct SendAgainBody: Encodable {
    let body: Doc
    let attachmentIds: [String]
    let stampSlug: String?

    enum CodingKeys: String, CodingKey { case body, attachmentIds, stampSlug }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(body, forKey: .body)
        try c.encode(attachmentIds, forKey: .attachmentIds)
        try c.encode(stampSlug, forKey: .stampSlug)
    }
}

struct SaveDiscussionDraftBody: Encodable { let title: String; let body: Doc; let version: Int; let color: String }
struct EditDiscussionBody: Encodable { let title: String; let body: Doc; let color: String; let attachmentIds: [String] }
struct SaveEmailDraftBody: Encodable { let subject: String; let text: String; let version: Int }
struct ProfileBody: Encodable { let username: String; let firstName: String; let lastName: String; let timezone: String }

struct NotifyChange: Encodable {
    let paused: Bool?
    let values: [String: Bool]?
}
