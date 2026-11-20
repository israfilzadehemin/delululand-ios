import DLData
import DLNetwork
import Foundation
import Observation

/// Optimistic send (doc "Delululand — Optimistic Send" OS1–OS14; web emails/outbox.ts): a thread
/// reply shows as a bubble at once and is sent here, outliving the thread screen for the app's life
/// (OS10). One email per thread can be in the air (OS7): the reply draft holds it until the send
/// succeeds, so the draft version doubles as the idempotency key; a 409 is reconciled (OS8).
@MainActor
@Observable
final class EmailOutbox {
    static let shared = EmailOutbox()

    /// OS8: no answer within this long counts as failed.
    static let sendTimeout: Duration = .seconds(20)

    enum Status: Equatable, Sendable { case sending, failed }

    enum FailKind: Equatable, Sendable { case offline, timeout, server, credits, refused }

    struct Fail: Equatable, Sendable {
        let kind: FailKind
        var message = ""
        /// OS5: what Retry can fix.
        var retryable: Bool { kind == .offline || kind == .timeout || kind == .server }
    }

    /// What the draft held at Send: saved again on a retry from a composer that opened later.
    struct Snapshot: Equatable, Sendable {
        let text: String
        let replyToId: String?
    }

    struct Entry: Equatable, Sendable {
        let threadId: PublicID
        /// The bubble: a provisional email with a `local-` id.
        let email: Email
        let snapshot: Snapshot
        var status: Status
        var fail: Fail?
        var attIds: [String] { email.attachments.map(\.id) }
    }

    enum Resolution {
        /// `credits` is nil when a retry found the email had landed already (OS8).
        case sent(Email, EmailCredits?)
        case cancelled([String])
    }

    private(set) var entries: [PublicID: Entry] = [:]

    /// OS11: these have spent their credit already.
    var sendingCount: Int { entries.values.filter { $0.status == .sending }.count }

    @ObservationIgnored private var prepares: [PublicID: @MainActor () async throws -> Int] = [:]
    @ObservationIgnored private var listeners: [UUID: (PublicID, Resolution) -> Void] = [:]
    @ObservationIgnored private var api: API?
    @ObservationIgnored private var seq = 0

    func entry(_ threadId: PublicID) -> Entry? { entries[threadId] }

    /// Sent or cancelled: the thread adds the real email, the composer releases its hold.
    func listen(_ fn: @escaping (PublicID, Resolution) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = fn
        return id
    }

    func unlisten(_ id: UUID) { listeners[id] = nil }

    /// The open composer saves the held draft through its own saver (no race with its autosave).
    func bind(_ threadId: PublicID, _ prepare: @escaping @MainActor () async throws -> Int) { prepares[threadId] = prepare }

    func unbind(_ threadId: PublicID) { prepares[threadId] = nil }

    func provisional(threadId: PublicID, senderId: PublicID, text: String, attachments: [Att], replyTo: EmailQuote?, now: Date = Date()) -> Email {
        seq += 1
        let ms = Int(now.timeIntervalSince1970 * 1000)
        return Email(
            id: "local-\(String(ms, radix: 36))-\(seq)",
            threadId: threadId,
            senderId: senderId,
            // As the API stores it (EmailText.forSend): CRLF → LF, then stripped.
            text: normalize(text).trimmingCharacters(in: .whitespacesAndNewlines),
            sentAt: DLTime.iso(now),
            attachments: attachments,
            replyTo: replyTo
        )
    }

    /// OS3: the bubble shows now; the save and the send run behind it.
    func enqueue(_ email: Email, snapshot: Snapshot, api: API, prepare: @escaping @MainActor () async throws -> Int) {
        let id = email.threadId
        guard entries[id] == nil else { return }
        self.api = api
        prepares[id] = prepare
        entries[id] = Entry(threadId: id, email: email, snapshot: snapshot, status: .sending)
        run(id)
    }

    /// OS5: Retry (offered only for what it can fix).
    func retry(_ threadId: PublicID) {
        guard var e = entries[threadId], e.status == .failed else { return }
        e.status = .sending
        e.fail = nil
        entries[threadId] = e
        run(threadId)
    }

    /// OS6: Cancel discards it; the composer clears the draft and deletes its attachments.
    func cancel(_ threadId: PublicID) {
        guard let e = entries[threadId], e.status == .failed else { return }
        entries[threadId] = nil
        notify(threadId, .cancelled(e.attIds))
    }

    private func notify(_ threadId: PublicID, _ r: Resolution) {
        listeners.values.forEach { $0(threadId, r) }
    }

    private func run(_ threadId: PublicID) {
        guard let e = entries[threadId], let api else { return }
        let prepare = prepares[threadId]
        Task {
            do {
                let (email, credits) = try await Self.withTimeout { try await Self.attempt(e, api: api, prepare: prepare) }
                guard entries[threadId] != nil else { return }
                entries[threadId] = nil
                notify(threadId, .sent(email, credits))
            } catch {
                guard var cur = entries[threadId] else { return }
                cur.status = .failed
                cur.fail = Self.classify(error)
                entries[threadId] = cur
            }
        }
    }

    private static func attempt(_ e: Entry, api: API, prepare: (@MainActor () async throws -> Int)?) async throws -> (Email, EmailCredits?) {
        let version: Int
        do {
            if let prepare {
                version = try await prepare()
            } else {
                let d = try await api.emailDraft(key: e.threadId)
                version = try await api.saveEmailDraft(key: e.threadId, subject: "", text: e.snapshot.text, version: d.version, replyToId: e.snapshot.replyToId).version
            }
        } catch let x as DraftSaver.FlushError where x.conflict {
            return try await reconcile(e, api: api)
        } catch let x as APIError where x.code == "DRAFT_CONFLICT" {
            return try await reconcile(e, api: api)
        }
        do {
            let s = try await api.reply(threadId: e.threadId, draftVersion: version)
            return (s.email, s.credits)
        } catch let x as APIError where x.code == "DRAFT_CONFLICT" {
            return try await reconcile(e, api: api)
        }
    }

    /// OS8: the draft moved on. Still holding this email → send at its version; empty → it landed.
    private static func reconcile(_ e: Entry, api: API) async throws -> (Email, EmailCredits?) {
        let d = try await api.emailDraft(key: e.threadId)
        let ids = Set(e.attIds)
        let blank = d.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let holds = normalize(d.text).trimmingCharacters(in: .whitespacesAndNewlines) == e.email.text && Set(d.attachments.map(\.id)) == ids
        if holds, !blank || !d.attachments.isEmpty {
            let s = try await api.reply(threadId: e.threadId, draftVersion: d.version)
            return (s.email, s.credits)
        }
        if blank, d.attachments.isEmpty {
            let items = try await api.thread(id: e.threadId).emails.items
            let landed = items.first { $0.senderId == e.email.senderId && $0.text == e.email.text && Set($0.attachments.map(\.id)) == ids }
                ?? items.first { $0.senderId == e.email.senderId && $0.text == e.email.text }
            if let landed { return (landed, nil) }
        }
        throw APIError(status: 409, code: "DRAFT_CONFLICT", message: "")
    }

    struct TimedOut: Error {}

    private static func withTimeout<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(for: sendTimeout)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    static func classify(_ error: Error) -> Fail {
        if error is TimedOut || error is CancellationError { return Fail(kind: .timeout) }
        if let e = error as? APIError {
            if e.status == 0 { return Fail(kind: .offline) }
            if e.code == "NO_CREDITS" { return Fail(kind: .credits) }
            if e.status >= 500 { return Fail(kind: .server) }
            if e.code == "DRAFT_CONFLICT" { return Fail(kind: .refused) }
            return Fail(kind: .refused, message: e.message)
        }
        // A failed autosave ("not saved") or no network at all.
        return Fail(kind: .offline)
    }

    /// Tests only.
    func reset() {
        entries = [:]
        prepares = [:]
    }
}
