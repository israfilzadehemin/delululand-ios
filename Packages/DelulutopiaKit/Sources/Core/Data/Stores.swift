import DLI18n
import DLNetwork
import Foundation
import Observation

/// When a screen re-reads its data (web `src/live/liveUpdates.ts`; Android `Refresher`):
/// - a live signal it names, or the stream (re)opening;
/// - while the stream is not live, every `poll` seconds (15 s lists and Home, 5 s threads);
/// - at the next deadline its data holds (`arrivesAt`, `windowEndsAt`, `renewsAt`), + 0.5 s, since a
///   window closing or an arrival happens with no write to announce it.
@MainActor
public final class Refresher {
    public static let listPoll: Double = 15
    public static let threadPoll: Double = 5

    private let live: LiveUpdates
    private let signals: Set<String>
    private let poll: Double
    private let deadlines: @MainActor () -> [String?]
    private let reload: @MainActor () async -> Void
    private var tasks: [Task<Void, Never>] = []
    private var deadlineTask: Task<Void, Never>?

    public init(
        live: LiveUpdates,
        signals: Set<String>,
        poll: Double = Refresher.listPoll,
        deadlines: @escaping @MainActor () -> [String?] = { [] },
        reload: @escaping @MainActor () async -> Void
    ) {
        self.live = live
        self.signals = signals
        self.poll = poll
        self.deadlines = deadlines
        self.reload = reload
    }

    public func start() {
        guard tasks.isEmpty else { return }
        let stream = live.signals()
        let names = signals
        tasks.append(Task { [weak self] in
            for await signal in stream {
                guard signal.name == LiveSignal.ready || names.contains(signal.name) else { continue }
                guard let self else { return }
                await self.reload()
                self.armDeadline()
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.poll ?? 15))
                guard let self, !Task.isCancelled else { return }
                if !self.live.isLive {
                    await self.reload()
                    self.armDeadline()
                }
            }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        deadlineTask?.cancel()
    }

    /// Call after each successful load.
    public func armDeadline() {
        deadlineTask?.cancel()
        let now = DLTime.now
        guard let next = deadlines().compactMap({ DLTime.date($0) }).filter({ $0 > now }).min() else { return }
        let wait = next.timeIntervalSince(now) + 0.5
        guard wait < 6 * 60 * 60 else { return }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            await self.reload()
            self.armDeadline()
        }
    }
}

/// Who is signed in on this device (FS-A2, FS-A13).
@MainActor
@Observable
public final class SessionStore {
    public enum State: Equatable, Sendable {
        case unknown
        case signedOut
        /// The start check could not reach the server; the start screen offers Try again.
        case unreachable
        case signedIn(HomeSession)
    }

    public private(set) var state: State = .unknown
    @ObservationIgnored private let api: API
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init(api: API) {
        self.api = api
        // FS-A13: a 401 NO_SESSION anywhere returns the app to the start.
        observer = NotificationCenter.default.addObserver(forName: .dlSessionEnded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state = .signedOut }
        }
    }

    /// FS-A2: a session cookie that the API still accepts opens Home straight away.
    public func refresh() async {
        do {
            state = .signedIn(try await api.homeSession())
        } catch let error as APIError {
            if error.status == 401 {
                state = .signedOut
            } else if case .signedIn = state {
                return
            } else {
                state = .unreachable
            }
        } catch {
            if case .signedIn = state { return }
            state = .unreachable
        }
    }

    /// FS-A11: ends this device's session only; the entry pass stays, so the cards come back.
    public func logout() async {
        try? await api.logout()
        state = .signedOut
    }

    /// For previews and tests.
    public func setState(_ state: State) {
        self.state = state
    }

    public var me: Person? {
        if case let .signedIn(s) = state { return s.me }
        return nil
    }
}

/// `GET /api/home`, shared by every screen that needs the friend, the moods, the badges or
/// `draftEmpty` (web `useHome`; Android `HomeRepository`). Refetched on the signals that touch Home,
/// polled every 15 s while the live stream is down, and at the next arrival / window end / renewal.
@MainActor
@Observable
public final class HomeStore {
    public private(set) var home: Home?
    public private(set) var offline = false
    public private(set) var moods: [Mood] = Moods.defaults
    public private(set) var moodLimit = Moods.limit
    /// The universe's own list arrived (custom moods can be added).
    public private(set) var moodsLoaded = false

    @ObservationIgnored private let api: API
    @ObservationIgnored private let live: LiveUpdates
    @ObservationIgnored private var refresher: Refresher?
    @ObservationIgnored private var moodTask: Task<Void, Never>?
    @ObservationIgnored private var languageObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var again = false

    public init(api: API, live: LiveUpdates) {
        self.api = api
        self.live = live
    }

    /// Called once the session is known (shell shown).
    public func start() {
        guard refresher == nil else { return }
        let refresher = Refresher(
            live: live,
            signals: ["letter", "discussion", "comment", "email", "reaction", "board", "mood", "moods", "profile", "universe", "language"],
            deadlines: { [weak self] in self?.deadlines() ?? [] },
            reload: { [weak self] in await self?.load() }
        )
        self.refresher = refresher
        refresher.start()
        let stream = live.signals()
        moodTask = Task { [weak self] in
            for await signal in stream where signal.name == "moods" {
                await self?.loadMoods()
            }
        }
        // L8: after a switch, the server's own words (default moods, stamps) come again in the new language.
        languageObserver = NotificationCenter.default.addObserver(forName: .dlLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadWords() }
        }
        Task {
            await load()
            await loadMoods()
        }
    }

    private func reloadWords() {
        Task {
            await load()
            await loadMoods()
        }
    }

    public func stop() {
        refresher?.stop()
        refresher = nil
        moodTask?.cancel()
        moodTask = nil
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        languageObserver = nil
        home = nil
        offline = false
        moodsLoaded = false
        moods = Moods.defaults
    }

    public func load() async {
        if loading {
            again = true
            return
        }
        loading = true
        defer { loading = false }
        repeat {
            again = false
            do {
                home = try await api.home()
                offline = false
                // L8: the account's language wins on every device; another device's pick arrives here.
                if let lang = Lang.parse(home?.me.language), lang != I18n.shared.lang { I18n.shared.set(lang) }
                refresher?.armDeadline()
            } catch let error as APIError {
                if error.isOffline { offline = true }
            } catch {}
        } while again
    }

    public func loadMoods() async {
        guard let catalogue = try? await api.moods() else { return }
        moods = catalogue.moods
        moodLimit = catalogue.limit ?? Moods.limit
        moodsLoaded = true
    }

    /// Local patch after a write that answers with the new value (mood, board).
    public func patch(_ change: (inout Home) -> Void) {
        guard var h = home else { return }
        change(&h)
        home = h
    }

    public func refreshSoon() {
        Task { await load() }
    }

    /// For previews and screenshot tests.
    public func setHome(_ home: Home?) {
        self.home = home
    }

    private func deadlines() -> [String?] {
        guard let h = home else { return [] }
        return (h.from + h.to).flatMap { [$0.windowEndsAt, $0.arrivesAt] }
            + h.newDiscussions.map(\.arrivesAt) + [h.emailCredits?.renewsAt]
    }
}
