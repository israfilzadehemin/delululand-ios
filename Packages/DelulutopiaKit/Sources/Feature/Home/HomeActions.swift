import DLData
import DLI18n
import DLNetwork
import DLUI
import Foundation
import Observation

/// Every write Home makes (web home/HomeScreen.tsx, board): moods, the board and its reaction and
/// note. Results update the shared Home state at once; the server confirms on the next load.
@MainActor
@Observable
final class HomeActions {
    let backend: Backend
    private var lastRefetch = Date.distantPast
    private var tellingSeen: Set<Int> = []

    init(backend: Backend) {
        self.backend = backend
    }

    private var store: HomeStore { backend.home }
    private var api: API { backend.api }

    /// A row crossed a deadline here: show the new state now, then let the server confirm it.
    func flipped() {
        let now = Date()
        if now.timeIntervalSince(lastRefetch) > 2 {
            lastRefetch = now
            store.refreshSoon()
        }
    }

    // MARK: Moods (S3, custom moods CM1–CM7)

    func setMood(_ key: String) async -> Bool {
        do {
            let change = try await api.setMood(key)
            let mood = store.moods.first { $0.key == key }
            store.patch { home in
                home.me.mood = change.mood
                home.me.moodSetAt = change.moodSetAt
                home.me.moodEmoji = mood?.emoji
                home.me.moodLabel = mood?.label
            }
            store.refreshSoon()
            return true
        } catch {
            return false
        }
    }

    /// Saves a new or edited mood; the error text on failure.
    func saveMood(editing: Mood?, emoji: String, label: String) async -> Result<Mood, MoodError> {
        let clean = Moods.normalise(label)
        do {
            let mood = if let editing {
                try await api.editMood(key: editing.key, emoji: emoji, label: clean)
            } else {
                try await api.addMood(emoji: emoji, label: clean)
            }
            await store.loadMoods()
            if editing != nil { store.refreshSoon() }
            return .success(mood)
        } catch {
            return .failure(MoodError(text: Self.moodError(error)))
        }
    }

    /// Nil on success (a mood already gone counts); else the error text.
    func deleteMood(_ key: String) async -> String? {
        do {
            try await api.deleteMood(key: key)
            await store.loadMoods()
            store.refreshSoon()
            return nil
        } catch let error as APIError where error.status == 404 {
            await store.loadMoods()
            return nil
        } catch {
            return Self.moodError(error)
        }
    }

    struct MoodError: Error {
        let text: String
    }

    private static func moodError(_ error: Error) -> String {
        if let e = error as? APIError, (400 ..< 500).contains(e.status), !e.code.hasPrefix("HTTP_") { return e.message }
        return t("home.notSavedTryAgain")
    }

    // MARK: Board (doc "Delululand — Board")

    /// B12, Q5: tell the server once that this version was on screen.
    func boardSeen(_ version: Int) {
        guard tellingSeen.insert(version).inserted else { return }
        Task {
            do {
                try await api.boardSeen(version: version)
            } catch {
                tellingSeen.remove(version)
            }
        }
    }

    enum PostResult {
        case posted
        case conflict(Board)
        case failed(String)
    }

    func postBoard(png: Data, baseVersion: Int, edit: Bool) async -> PostResult {
        if let tooLarge = API.UploadKind.doodle.precheck(png.count) { return .failed(tooLarge) }
        do {
            let board = try await api.postBoard(png: png, baseVersion: baseVersion, edit: edit)
            store.patch { home in
                home.board = board
                home.boardNew = false
            }
            store.refreshSoon()
            return .posted
        } catch let error as APIError {
            if let current = Self.changed(error) {
                store.patch { $0.board = current }
                return .conflict(current)
            }
            return .failed(error.isOffline ? t("board.postingFailed") : error.message)
        } catch {
            return .failed(t("board.postingFailed"))
        }
    }

    /// §R: one hand-drawn mark on the friend's doodle; nil removes it. Returns a notice, or nil.
    func react(_ board: Board, key: String?, friend: String) async -> String? {
        if key == board.reaction { return nil }
        store.patch { $0.board?.reaction = key }
        do {
            let view = if let key {
                try await api.reactBoard(version: board.version, reaction: key)
            } else {
                try await api.unreactBoard(version: board.version)
            }
            store.patch { $0.board = view }
            return nil
        } catch {
            let e = error as? APIError
            if let e, let current = Self.changed(e) {
                store.patch { $0.board = current }
                return t("board.friendJustPosted", ["friend": friend])
            }
            store.patch { $0.board = board }
            return (e?.isOffline ?? true) ? t("board.reactionNotSaved") : e!.message
        }
    }

    /// §C: the friend's one sticky note. A notice on failure, or nil.
    func comment(_ board: Board, text: String, friend: String) async -> String? {
        await boardWrite(friend: friend, fallback: t("board.commentNotPosted")) {
            try await $0.commentBoard(version: board.version, text: text)
        }
    }

    func uncomment(_ board: Board, friend: String) async -> String? {
        await boardWrite(friend: friend, fallback: t("board.commentNotDeleted")) {
            try await $0.uncommentBoard(version: board.version)
        }
    }

    private func boardWrite(friend: String, fallback: String, _ call: (API) async throws -> Board) async -> String? {
        do {
            let view = try await call(api)
            store.patch { $0.board = view }
            return nil
        } catch {
            guard let e = error as? APIError else { return fallback }
            if let current = Self.changed(e) {
                store.patch { $0.board = current }
                return t("board.friendJustPosted", ["friend": friend])
            }
            if e.code == "COMMENT_EXISTS" {
                store.refreshSoon()
                return e.message
            }
            return e.isOffline ? fallback : e.message
        }
    }

    private static func changed(_ error: APIError) -> Board? {
        error.code == "BOARD_CHANGED" ? error.extra["board"]?.decode(Board.self) : nil
    }

    // MARK: Letters

    func cancel(_ id: Int) async -> LetterActions.CancelResult {
        await LetterActions.cancel(id, backend: backend)
    }
}
