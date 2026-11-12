import Foundation

/// The API, one function per endpoint (Technical Design §5.2 and the story docs; web `src/api`;
/// Android `DelulutopiaApi`). Failures are `APIError`s.
public struct API: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    private struct Empty: Encodable {}

    private func q(_ pairs: [String: String?]) -> [String: String] {
        pairs.compactMapValues { $0 }
    }

    // MARK: Config and entry

    public func config() async throws -> ServerSettings { try await client.call("GET", "api/config") }

    public func enter(code: String) async throws -> Entered { try await client.call("POST", "api/entry", body: CodeBody(code: code)) }
    public func forgetEntry() async throws { try await client.run("POST", "api/entry/forget") }
    public func entry() async throws -> EntryView { try await client.call("GET", "api/universe/entry") }

    // MARK: Auth

    public func login(userId: Int, pin: String) async throws { try await client.run("POST", "api/auth/login", body: LoginBody(userId: userId, pin: pin)) }
    public func createPin(userId: Int, pin: String) async throws { try await client.run("POST", "api/auth/pin", body: LoginBody(userId: userId, pin: pin)) }
    public func logout() async throws { try await client.run("POST", "api/auth/logout") }
    public func changePin(current: String, new: String) async throws {
        try await client.run("POST", "api/me/pin", body: ChangePinBody(currentPin: current, newPin: new))
    }

    // MARK: Universe

    public func checkInvite(_ invite: String) async throws { try await client.run("POST", "api/invites/check", body: InviteBody(invite: invite)) }
    public func createUniverse(_ request: CreateUniverseRequest) async throws -> CreatedUniverse { try await client.call("POST", "api/universes", body: request) }
    public func join(username: String, timezone: String, pin: String) async throws {
        try await client.run("POST", "api/universe/join", body: JoinBody(username: username, timezone: timezone, pin: pin))
    }
    public func universe() async throws -> UniverseView { try await client.call("GET", "api/universe") }
    public func updateUniverse(name: String, welcome: String) async throws -> UniverseView {
        try await client.call("PUT", "api/universe", body: UniverseUpdate(name: name, welcome: welcome))
    }
    public func rotateKey() async throws -> KeyCode { try await client.call("POST", "api/universe/code") }

    // MARK: Home and moods

    public func homeSession() async throws -> HomeSession { try await client.call("GET", "api/home") }
    public func home() async throws -> Home { try await client.call("GET", "api/home") }
    public func homeCounts() async throws -> HomeCounts { try await client.call("GET", "api/home/counts") }
    public func setMood(_ mood: String) async throws -> MoodChange { try await client.call("PUT", "api/me/mood", body: MoodBody(mood: mood)) }
    public func moods() async throws -> MoodCatalogue { try await client.call("GET", "api/moods") }
    public func addMood(emoji: String, label: String) async throws -> Mood {
        try await client.call("POST", "api/moods", body: MoodEditBody(emoji: emoji, label: label))
    }
    public func editMood(key: String, emoji: String, label: String) async throws -> Mood {
        try await client.call("PUT", "api/moods/\(key)", body: MoodEditBody(emoji: emoji, label: label))
    }
    public func deleteMood(key: String) async throws { try await client.run("DELETE", "api/moods/\(key)") }

    // MARK: Board (doc "Delululand — Board" §3)

    /// `edit` true when the doodle replaces the latest one in place (Board §8).
    public func postBoard(png: Data, baseVersion: Int, edit: Bool) async throws -> Board {
        var fields = ["baseVersion": String(baseVersion)]
        if edit { fields["edit"] = "true" }
        return try await client.upload("api/board", fields: fields, filename: "board.png", mime: "image/png", data: png, timeout: 60)
    }
    public func reactBoard(version: Int, reaction: String) async throws -> Board {
        try await client.call("PUT", "api/board/reaction", body: ReactionVersionBody(version: version, reaction: reaction))
    }
    public func unreactBoard(version: Int) async throws -> Board {
        try await client.call("DELETE", "api/board/reaction", query: ["version": String(version)])
    }
    public func commentBoard(version: Int, text: String) async throws -> Board {
        try await client.call("PUT", "api/board/comment", body: BoardCommentBody(version: version, text: text))
    }
    public func uncommentBoard(version: Int) async throws -> Board {
        try await client.call("DELETE", "api/board/comment", query: ["version": String(version)])
    }
    public func boardSeen(version: Int) async throws { try await client.run("POST", "api/board/seen", body: VersionBody(version: version)) }

    // MARK: Letters and the draft

    public func draft() async throws -> Draft { try await client.call("GET", "api/draft") }
    public func saveDraft(body: Doc, pinnedLetterId: Int?, stampSlug: String?, version: Int) async throws -> Saved {
        try await client.call("PUT", "api/draft", body: SaveDraftBody(body: body, pinnedLetterId: pinnedLetterId, stampSlug: stampSlug, version: version))
    }
    public func deleteDraftAttachment(id: String) async throws { try await client.run("DELETE", "api/draft/attachments/\(id)") }
    public func send(draftVersion: Int) async throws -> Sent { try await client.call("POST", "api/letters", body: DraftVersionBody(draftVersion: draftVersion)) }
    public func letter(id: Int) async throws -> LetterFull { try await client.call("GET", "api/letters/\(id)") }
    public func letters(cursor: String? = nil, limit: Int? = nil, direction: String? = nil) async throws -> LetterPage {
        try await client.call("GET", "api/letters", query: q(["cursor": cursor, "limit": limit.map(String.init), "direction": direction]))
    }
    public func cancelLetter(id: Int) async throws -> DraftVersion { try await client.call("DELETE", "api/letters/\(id)") }
    public func sendAgain(id: Int, body: Doc, attachmentIds: [String], stampSlug: String?) async throws -> LetterFull {
        try await client.call("PUT", "api/letters/\(id)", body: SendAgainBody(body: body, attachmentIds: attachmentIds, stampSlug: stampSlug))
    }
    public func discardEdit(id: Int) async throws { try await client.run("DELETE", "api/letters/\(id)/edit") }
    public func keepInDraft(id: Int, body: Doc) async throws -> DraftVersion {
        try await client.call("POST", "api/letters/\(id)/edit/keep-in-draft", body: BodyOnly(body: body))
    }
    public func stamps() async throws -> StampCatalogue { try await client.call("GET", "api/stamps") }

    // MARK: Discussions

    public func discussions(cursor: String? = nil, limit: Int? = nil, archived: Bool? = nil) async throws -> DPage {
        try await client.call("GET", "api/discussions", query: q(["cursor": cursor, "limit": limit.map(String.init), "archived": archived.map { $0 ? "true" : "false" }]))
    }
    public func discussion(id: Int) async throws -> DFull { try await client.call("GET", "api/discussions/\(id)") }
    public func comments(discussionId: Int, cursor: String? = nil, limit: Int? = nil, from: String? = nil) async throws -> DComments {
        try await client.call("GET", "api/discussions/\(discussionId)/comments", query: q(["cursor": cursor, "limit": limit.map(String.init), "from": from]))
    }
    public func comment(discussionId: Int, text: String) async throws -> DComment {
        try await client.call("POST", "api/discussions/\(discussionId)/comments", body: TextBody(text: text))
    }
    public func editComment(discussionId: Int, commentId: Int, text: String) async throws -> DComment {
        try await client.call("PATCH", "api/discussions/\(discussionId)/comments/\(commentId)", body: TextBody(text: text))
    }
    public func deleteComment(discussionId: Int, commentId: Int) async throws {
        try await client.run("DELETE", "api/discussions/\(discussionId)/comments/\(commentId)")
    }
    public func discussionSeen(id: Int) async throws { try await client.run("POST", "api/discussions/\(id)/seen") }
    /// Cancel inside the window and Delete at any time: the same call.
    public func deleteDiscussion(id: Int) async throws { try await client.run("DELETE", "api/discussions/\(id)") }
    public func editDiscussion(id: Int, title: String, body: Doc, color: String, attachmentIds: [String]) async throws -> DFull {
        try await client.call("PUT", "api/discussions/\(id)", body: EditDiscussionBody(title: title, body: body, color: color, attachmentIds: attachmentIds))
    }
    public func discardDiscussionEdit(id: Int) async throws { try await client.run("DELETE", "api/discussions/\(id)/edit") }
    public func archive(id: Int) async throws -> DFull { try await client.call("POST", "api/discussions/\(id)/archive") }
    public func unarchive(id: Int) async throws -> DFull { try await client.call("DELETE", "api/discussions/\(id)/archive") }
    public func discussionDraft() async throws -> DDraft { try await client.call("GET", "api/discussions/draft") }
    public func saveDiscussionDraft(title: String, body: Doc, version: Int, color: String) async throws -> Saved {
        try await client.call("PUT", "api/discussions/draft", body: SaveDiscussionDraftBody(title: title, body: body, version: version, color: color))
    }
    public func deleteDiscussionDraftAttachment(id: String) async throws { try await client.run("DELETE", "api/discussions/draft/attachments/\(id)") }
    public func post(draftVersion: Int) async throws -> DPosted { try await client.call("POST", "api/discussions", body: DraftVersionBody(draftVersion: draftVersion)) }

    // MARK: Emails (key = "new" or a thread id)

    public func threads(cursor: String? = nil, limit: Int? = nil) async throws -> ThreadPage {
        try await client.call("GET", "api/emails/threads", query: q(["cursor": cursor, "limit": limit.map(String.init)]))
    }
    public func thread(id: Int) async throws -> ThreadFull { try await client.call("GET", "api/emails/threads/\(id)") }
    public func olderEmails(threadId: Int, cursor: String, limit: Int = 20) async throws -> EmailList {
        try await client.call("GET", "api/emails/threads/\(threadId)/emails", query: ["cursor": cursor, "limit": String(limit)])
    }
    public func threadSeen(id: Int) async throws { try await client.run("POST", "api/emails/threads/\(id)/seen") }
    public func credits() async throws -> EmailCredits { try await client.call("GET", "api/emails/credits") }
    public func emailDraft(key: String) async throws -> EmailDraft { try await client.call("GET", "api/emails/drafts/\(key)") }
    public func saveEmailDraft(key: String, subject: String, text: String, version: Int) async throws -> Saved {
        try await client.call("PUT", "api/emails/drafts/\(key)", body: SaveEmailDraftBody(subject: subject, text: text, version: version))
    }
    public func deleteEmailDraftAttachment(key: String, id: String) async throws {
        try await client.run("DELETE", "api/emails/drafts/\(key)/attachments/\(id)")
    }
    public func sendNewEmail(draftVersion: Int) async throws -> EmailSent {
        try await client.call("POST", "api/emails/threads", body: DraftVersionBody(draftVersion: draftVersion))
    }
    public func reply(threadId: Int, draftVersion: Int) async throws -> EmailSent {
        try await client.call("POST", "api/emails/threads/\(threadId)/emails", body: DraftVersionBody(draftVersion: draftVersion))
    }

    // MARK: Reactions (target = discussions | comments | emails)

    public func react(target: String, id: Int, emoji: String) async throws -> Reactions {
        try await client.call("PUT", "api/reactions/\(target)/\(id)", body: EmojiBody(emoji: emoji))
    }
    public func unreact(target: String, id: Int, emoji: String) async throws -> Reactions {
        try await client.call("DELETE", "api/reactions/\(target)/\(id)", body: EmojiBody(emoji: emoji))
    }

    // MARK: Profile and settings

    public func profile() async throws -> Profile { try await client.call("GET", "api/me/profile") }
    public func saveProfile(username: String, firstName: String, lastName: String, timezone: String) async throws -> Profile {
        try await client.call("PUT", "api/me/profile", body: ProfileBody(username: username, firstName: firstName, lastName: lastName, timezone: timezone))
    }
    public func uploadAvatar(jpeg: Data) async throws -> Profile {
        try await client.upload("api/me/avatar", fields: [:], filename: "avatar.jpg", mime: "image/jpeg", data: jpeg, timeout: 60)
    }
    public func removeAvatar() async throws -> Profile { try await client.call("DELETE", "api/me/avatar") }
    public func notifications() async throws -> NotifySettings { try await client.call("GET", "api/me/notifications") }
    public func saveNotifications(paused: Bool? = nil, values: [String: Bool]? = nil) async throws -> NotifySettings {
        try await client.call("PUT", "api/me/notifications", body: NotifyChange(paused: paused, values: values))
    }

    // MARK: Attachments (web src/media/upload.ts)

    public enum UploadKind: String, Sendable {
        case photo, audio, video, doodle

        var timeout: TimeInterval {
            switch self {
            case .photo: 120
            case .audio: 180
            case .video: 360
            case .doodle: 60
            }
        }

        public var maxBytes: Int {
            switch self {
            case .photo: 10 * 1024 * 1024
            case .audio: 60 * 1024 * 1024
            case .video: 100 * 1024 * 1024
            case .doodle: 2 * 1024 * 1024
            }
        }

        public var tooLarge: String {
            switch self {
            case .photo: "This photo is larger than 10 MB"
            case .audio: "This audio file is larger than 60 MB"
            case .video: "This video is larger than 100 MB"
            case .doodle: "This doodle is larger than 2 MB"
            }
        }

        /// The refusal sentence when `bytes` is over the limit, before uploading.
        public func precheck(_ bytes: Int) -> String? { bytes > maxBytes ? tooLarge : nil }
    }

    /// Uploads to a draft's attachment path (`api/draft/attachments`, `api/discussions/draft/attachments`,
    /// `api/emails/drafts/{key}/attachments`). The size check runs before any byte leaves the phone (O4).
    public func upload(
        to path: String,
        kind: UploadKind,
        data: Data,
        filename: String,
        mime: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Att {
        guard data.count <= kind.maxBytes else {
            throw APIError(status: 413, code: "TOO_LARGE", message: kind.tooLarge)
        }
        return try await client.upload(path, fields: ["kind": kind.rawValue], filename: filename, mime: mime, data: data, timeout: kind.timeout, progress: progress)
    }
}
