import DLNetwork
import Foundation
import Observation

/// S6's rows, newest first (web letters/useLetterRows.ts): page 1 re-read on `letter` signals and
/// polled while the stream is down; older pages by keyset, merged so a row never shows twice. Shared
/// by the list and by S7's swipe between letters, so both walk the same order.
@MainActor
@Observable
public final class LettersStore {
    public private(set) var head: [LetterRow]?
    public private(set) var older: [LetterRow] = []
    public private(set) var nextCursor: String?
    public private(set) var loadingMore = false
    public private(set) var failed = false

    @ObservationIgnored private let api: API
    @ObservationIgnored private let live: LiveUpdates
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var loading = false

    static let page = 20

    public init(api: API, live: LiveUpdates) {
        self.api = api
        self.live = live
    }

    public var loaded: Bool { head != nil }
    public var hasMore: Bool { nextCursor != nil }

    /// Page 1 as it is now, then older pages; a letter cancelled since must not linger from an older copy.
    public var rows: [LetterRow] {
        let fresh = head ?? []
        let seen = Set(fresh.map(\.id))
        let oldest = fresh.last
        let kept = older.filter { r in
            guard !seen.contains(r.id) else { return false }
            guard let oldest else { return true }
            return r.sentAt < oldest.sentAt || (r.sentAt == oldest.sentAt && r.id < oldest.id)
        }
        return fresh + kept
    }

    /// A screen that shows letters is on screen; the first one starts the refresh.
    public func attach() {
        users += 1
        if refresher != nil {
            Task { await loadHead() }
            return
        }
        let refresher = Refresher(live: live, signals: ["letter"], reload: { [weak self] in await self?.loadHead() })
        self.refresher = refresher
        refresher.start()
        Task { await loadHead() }
    }

    public func detach() {
        users = max(0, users - 1)
        if users == 0 {
            refresher?.stop()
            refresher = nil
        }
    }

    public func loadHead() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.letters(limit: Self.page)
            head = page.items
            if older.isEmpty { nextCursor = page.nextCursor }
            failed = false
        } catch {
            failed = true
        }
    }

    public func loadMore() {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        Task {
            do {
                let page = try await api.letters(cursor: cursor, limit: Self.page)
                older += page.items
                nextCursor = page.nextCursor
            } catch {}
            loadingMore = false
        }
    }

    public func refreshSoon() {
        Task { await loadHead() }
    }

    /// Sign-out: forget everything.
    public func clear() {
        refresher?.stop()
        refresher = nil
        users = 0
        head = nil
        older = []
        nextCursor = nil
        failed = false
    }
}
