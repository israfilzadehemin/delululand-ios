import DLI18n
import DLNetwork
import Foundation
import Observation

/// Autosave for a draft (FS-W3, FS-W4, O9; web `editor/DraftSaver.ts`; Android `DraftSaver`), for
/// letters, discussions and emails alike:
/// - saved no later than 2 s after the last change, and at once on leaving the screen;
/// - every save carries the version it was based on; `409 DRAFT_CONFLICT` stops autosave until the
///   user picks Load or Keep mine;
/// - a failed save shows "Couldn't save your draft" and retries every 10 s with the text untouched;
/// - Send flushes first, so what is sent is exactly what was on screen.
@MainActor
@Observable
public final class DraftSaver {
    public enum Status: Sendable { case clean, saving, saved, error, conflict }

    public struct FlushError: Error, LocalizedError {
        public let conflict: Bool
        public var errorDescription: String? {
            conflict ? t("common.newerVersion") : t("common.draftNotSaved")
        }
    }

    public private(set) var status: Status = .clean
    public private(set) var savedAt: String?
    public private(set) var serverVersion: Int?

    @ObservationIgnored public private(set) var version = 0
    @ObservationIgnored public private(set) var dirty = false
    @ObservationIgnored private let save: @MainActor (Int) async throws -> Saved
    @ObservationIgnored private let debounce: Double
    @ObservationIgnored private let retryAfter: Double
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var conflictVersion: Int?

    /// `save` reads the current content itself and saves it on top of the given version.
    public init(debounce: Double = 2, retryAfter: Double = 10, save: @escaping @MainActor (Int) async throws -> Saved) {
        self.save = save
        self.debounce = debounce
        self.retryAfter = retryAfter
    }

    /// The server's draft, at load or after Load in the conflict dialog.
    public func load(version: Int, savedAt: String?) {
        timer?.cancel()
        self.version = version
        dirty = false
        conflictVersion = nil
        serverVersion = nil
        status = .clean
        self.savedAt = savedAt
    }

    /// Anything saved changed (text, pin, stamp, title, colour).
    public func touch() {
        dirty = true
        if status == .conflict { return }
        schedule(after: debounce)
    }

    /// Before Send: the version the server holds once everything is saved.
    public func flush() async throws -> Int {
        for _ in 0..<3 {
            await inFlight?.value
            if status == .conflict { throw FlushError(conflict: true) }
            if !dirty {
                if status == .error { throw FlushError(conflict: false) }
                return version
            }
            await saveNow()
        }
        if status == .conflict { throw FlushError(conflict: true) }
        if dirty || status == .error { throw FlushError(conflict: false) }
        return version
    }

    /// The screen is left: save now, outliving the screen.
    public func flushOnLeave() {
        guard dirty, status != .conflict else { return }
        Task { await self.saveNow() }
    }

    /// The conflict dialog's Keep mine: re-send on top of the server's version.
    public func keepMine() {
        guard let v = conflictVersion else { return }
        version = v
        conflictVersion = nil
        serverVersion = nil
        dirty = true
        status = .saving
        Task { await saveNow() }
    }

    public func dispose() {
        timer?.cancel()
    }

    private func schedule(after seconds: Double) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() async {
        if let running = inFlight {
            await running.value
            if !dirty || status == .conflict { return }
        }
        if !dirty || status == .conflict { return }
        timer?.cancel()
        dirty = false
        status = .saving
        let based = version
        let task = Task { @MainActor [save] in
            do {
                let result = try await save(based)
                self.version = result.version
                self.status = .saved
                self.savedAt = result.savedAt
                if self.dirty { self.schedule(after: self.debounce) }
            } catch let error as APIError {
                self.dirty = true
                if error.code == "DRAFT_CONFLICT" {
                    self.conflictVersion = error.extra["serverVersion"]?.int
                    self.serverVersion = self.conflictVersion
                    self.status = .conflict
                } else {
                    self.status = .error
                    self.schedule(after: self.retryAfter)
                }
            } catch {
                self.dirty = true
                self.status = .error
                self.schedule(after: self.retryAfter)
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// `savedAt` of a refusal's extra, when it carries one.
    public static func savedAt(of error: APIError) -> String? {
        error.extra["savedAt"]?.string
    }
}
