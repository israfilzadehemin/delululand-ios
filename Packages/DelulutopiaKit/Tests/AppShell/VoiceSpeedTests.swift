@testable import DLUI
import DLI18n
import Foundation
import Testing

/// Voice-note speed (doc "Delululand — Voice Note Speed" VS3, VS4, VS9; web src/media/speed.test.tsx).
@Suite("Voice speed")
struct VoiceSpeedTests {
    @Test("Cycles 0.5× → 1× → 1.5× → 2× → 0.5× and starts at 1×")
    func cycle() {
        #expect(VoiceSpeed.defaultSpeed == 1)
        #expect(VoiceSpeed.next(0.5) == 1)
        #expect(VoiceSpeed.next(1) == 1.5)
        #expect(VoiceSpeed.next(1.5) == 2)
        #expect(VoiceSpeed.next(2) == 0.5)
    }

    @Test("Keeps the pick on this phone and ignores junk")
    func stored() {
        let name = "voice-speed-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(VoiceSpeed.stored(defaults) == 1)
        VoiceSpeed.store(1.5, defaults)
        #expect(VoiceSpeed.stored(defaults) == 1.5)
        defaults.set(Float(3), forKey: VoiceSpeed.key)
        #expect(VoiceSpeed.stored(defaults) == 1)
    }

    @Test("Writes the chip in each language")
    func labels() {
        #expect(VoiceSpeed.label(0.5, .en) == "0.5×")
        #expect(VoiceSpeed.label(1, .az) == "1×")
        #expect(VoiceSpeed.label(2, .ru) == "2×")
        #expect(VoiceSpeed.label(0.5, .fa) == "۰٫۵×")
        #expect(VoiceSpeed.label(1.5, .fa) == "۱٫۵×")
    }
}
