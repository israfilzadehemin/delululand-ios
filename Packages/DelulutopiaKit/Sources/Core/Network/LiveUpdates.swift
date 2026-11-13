import Foundation
import Observation

/// One change in this universe (Backend Refactor Plan items 6–9): its name and at most an id, never
/// content. `ready` means the stream (re)opened: anything fetched while it was down may be stale.
public struct LiveSignal: Sendable, Hashable {
    public let name: String
    public let id: Int?

    public init(name: String, id: Int? = nil) {
        self.name = name
        self.id = id
    }

    public static let ready = "ready"
}

/// Live updates (web `src/live/liveUpdates.ts`, iOS design I-4): one `/api/events` stream while the
/// app is in the foreground and signed in. Screens refetch only what a signal names. While the stream
/// is not live every screen polls exactly as the web does, so behaviour never depends on the stream.
/// A refused stream is retried after 30 s, doubling to 5 min; a stream the server closed reopens at once.
@MainActor
@Observable
public final class LiveUpdates {
    public private(set) var isLive = false

    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<LiveSignal>.Continuation] = [:]
    @ObservationIgnored private var retry: Double = 30

    public init(client: APIClient) {
        self.client = client
    }

    /// Every signal from now on. Ends when the caller's task is cancelled.
    public func signals() -> AsyncStream<LiveSignal> {
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.subscribers[id] = nil }
            }
        }
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isLive = false
    }

    private func emit(_ signal: LiveSignal) {
        for continuation in subscribers.values {
            continuation.yield(signal)
        }
    }

    private func run() async {
        while !Task.isCancelled {
            let wasLive = await listen()
            isLive = false
            if Task.isCancelled { return }
            let wait: Double
            if wasLive {
                wait = 1
                retry = 30
            } else {
                wait = retry
                retry = min(retry * 2, 300)
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    /// Reads one stream until it ends; true when it had become live.
    private func listen() async -> Bool {
        var request = client.makeRequest("GET", "api/events")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60 * 60
        var becameLive = false
        do {
            let (bytes, response) = try await client.session.bytes(for: request)
            client.absorb(response, for: request.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            var event: String?
            var data = ""
            for try await line in bytes.lines {
                if line.isEmpty {
                    dispatch(event: event, data: data, becameLive: &becameLive)
                    event = nil
                    data = ""
                } else if line.hasPrefix("event:") {
                    event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    // `lines` drops the blank separator line on some streams: dispatch on the next
                    // event line instead, so a signal is never held back.
                } else if line.hasPrefix("data:") {
                    data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if let e = event {
                        dispatch(event: e, data: data, becameLive: &becameLive)
                        event = nil
                        data = ""
                    }
                }
            }
        } catch {
            return becameLive
        }
        return becameLive
    }

    private func dispatch(event: String?, data: String, becameLive: inout Bool) {
        guard let event else { return }
        if event == LiveSignal.ready {
            becameLive = true
            isLive = true
            retry = 30
            emit(LiveSignal(name: LiveSignal.ready))
        } else {
            let id = (try? JSONDecoder().decode([String: JSONValue].self, from: Data(data.utf8)))?["id"]?.int
            emit(LiveSignal(name: event, id: id))
        }
    }
}
