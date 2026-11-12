@testable import DLData
import DLNetwork
import Foundation
import Testing

@Suite("Time")
struct TimeTests {
    @Test("Countdowns are m:ss, rounded up, never negative")
    func countdown() {
        #expect(DLTime.countdown(1721.2) == "28:42")
        #expect(DLTime.countdown(0) == "0:00")
        #expect(DLTime.countdown(-5) == "0:00")
        #expect(DLTime.countdown(3600) == "60:00")
    }

    @Test("ISO durations read as seconds")
    func durations() {
        #expect(DLTime.isoDuration("PT1H") == 3600)
        #expect(DLTime.isoDuration("PT6M") == 360)
        #expect(DLTime.isoDuration("PT30S") == 30)
        #expect(DLTime.durationText("PT6M") == "6:00")
    }

    @Test("Instants parse with and without fractions; letter states flip at the deadlines")
    func states() throws {
        let sent = try #require(DLTime.date("2026-11-12T10:00:00Z"))
        #expect(DLTime.date("2026-11-12T10:00:00.250Z") != nil)
        let window = "2026-11-12T10:05:00Z"
        let arrives = "2026-11-12T11:00:00Z"
        #expect(LetterState.of(now: sent, windowEndsAt: window, arrivesAt: arrives, readAt: nil) == LetterState.inReach)
        #expect(LetterState.of(now: sent.addingTimeInterval(600), windowEndsAt: window, arrivesAt: arrives, readAt: nil) == LetterState.inTransit)
        #expect(LetterState.of(now: sent.addingTimeInterval(4000), windowEndsAt: window, arrivesAt: arrives, readAt: nil) == LetterState.delivered)
    }

    @Test("Wall clocks follow the zone; unknown zones read as UTC")
    func wallClock() throws {
        let noon = try #require(DLTime.date("2026-11-12T12:00:00Z"))
        #expect(DLTime.wallClock(noon, zone: "Asia/Tehran").hour == 15)
        #expect(DLTime.wallClock(noon, zone: "Nowhere/City").hour == 12)
        #expect(DLTime.city(of: "America/New_York") == "New York")
    }
}

@Suite("Moods")
struct MoodTests {
    @Test("Labels: rule, taken, and fine")
    func labels() {
        #expect(Moods.labelProblem("", catalogue: Moods.defaults, exceptKey: nil) == nil)
        #expect(Moods.labelProblem("sad", catalogue: Moods.defaults, exceptKey: nil) == Moods.labelTaken)
        #expect(Moods.labelProblem("Sad", catalogue: Moods.defaults, exceptKey: "SAD") == nil)
        #expect(Moods.labelProblem("!!!", catalogue: Moods.defaults, exceptKey: nil) == Moods.labelRule)
        #expect(Moods.labelProblem("Seventeen letters", catalogue: Moods.defaults, exceptKey: nil) == Moods.labelRule)
        #expect(Moods.labelProblem("  Sunny   day ", catalogue: Moods.defaults, exceptKey: nil) == nil)
        #expect(Moods.text("SAD") == "🌧️ Sad")
        #expect(Moods.text("X", emoji: "🍕", label: "Pizza") == "🍕 Pizza")
    }
}

@MainActor
@Suite("Draft saver")
struct DraftSaverTests {
    @MainActor
    final class Recorder {
        var calls: [Int] = []
        var fail = true
    }

    @Test("A conflict stops autosave until Keep mine")
    func conflict() async throws {
        let recorder = Recorder()
        let saver = DraftSaver(debounce: 0.01, retryAfter: 60) { version in
            recorder.calls.append(version)
            if recorder.fail {
                recorder.fail = false
                throw APIError(status: 409, code: "DRAFT_CONFLICT", message: "", extra: ["serverVersion": .number(5)])
            }
            return Saved(version: version + 1, savedAt: "2026-11-12T10:00:00Z")
        }
        saver.load(version: 2, savedAt: nil)
        saver.touch()
        try await Task.sleep(for: .milliseconds(200))
        #expect(saver.status == .conflict)
        #expect(saver.serverVersion == 5)
        await #expect(throws: DraftSaver.FlushError.self) { _ = try await saver.flush() }
        saver.keepMine()
        try await Task.sleep(for: .milliseconds(200))
        #expect(saver.status == .saved)
        #expect(saver.version == 6)
        #expect(recorder.calls == [2, 5])
    }
}
