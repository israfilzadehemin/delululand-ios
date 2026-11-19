import DLI18n
import Foundation

/// Voice-note playback speed (doc "Delululand — Voice Note Speed" VS3–VS9; web src/media/speed.ts).
/// One chip on every voice-note player cycles 0.5× → 1× → 1.5× → 2× → 0.5×; the last pick is kept on
/// this phone (VS4, UserDefaults) and applies to every note.
public enum VoiceSpeed {
    public static let speeds: [Float] = [0.5, 1, 1.5, 2]
    public static let defaultSpeed: Float = 1
    static let key = "dl.voiceSpeed"

    public static func next(_ s: Float) -> Float {
        let i = speeds.firstIndex(of: s) ?? speeds.firstIndex(of: defaultSpeed)!
        return speeds[(i + 1) % speeds.count]
    }

    /// The kept pick; anything unknown reads as 1×.
    public static func stored(_ defaults: UserDefaults = .standard) -> Float {
        let v = defaults.float(forKey: key)
        return speeds.contains(v) ? v : defaultSpeed
    }

    public static func store(_ s: Float, _ defaults: UserDefaults = .standard) {
        defaults.set(s, forKey: key)
    }

    /// "1.5×"; Persian digits and the Persian decimal sign in Persian, "۱٫۵×" (VS9).
    public static func label(_ s: Float, _ lang: Lang = I18n.shared.lang) -> String {
        let n = s.rounded() == s ? String(Int(s)) : String(s)
        guard lang == .fa else { return "\(n)×" }
        return localDigits(n, .fa).replacingOccurrences(of: ".", with: "\u{066B}") + "×"
    }
}
