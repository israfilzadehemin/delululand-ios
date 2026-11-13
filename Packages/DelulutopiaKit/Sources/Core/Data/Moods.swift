import DLI18n
import DLNetwork
import Foundation

/// Moods (web `src/text/moods.ts`, doc "Delululand — Moods"). The API's catalogue is the source; these
/// show while it loads.
public enum Moods {
    /// Built when asked, so the labels are in the language in force.
    public static var defaults: [Mood] {
        [
        ("HAPPY", "😊", t("mood.HAPPY")), ("CALM", "🍵", t("mood.CALM")), ("CURIOUS", "🤔", t("mood.CURIOUS")), ("INSPIRED", "✨", t("mood.INSPIRED")),
        ("BUSY", "🏃", t("mood.BUSY")), ("TIRED", "😴", t("mood.TIRED")), ("SAD", "🌧️", t("mood.SAD")), ("MISSING_YOU", "💌", t("mood.MISSING_YOU")),
        ("LOVED", "🥰", t("mood.LOVED")), ("GRATEFUL", "🙏", t("mood.GRATEFUL")), ("EXCITED", "🤩", t("mood.EXCITED")), ("PLAYFUL", "😜", t("mood.PLAYFUL")),
        ("COZY", "🧸", t("mood.COZY")), ("HOPEFUL", "🌱", t("mood.HOPEFUL")), ("PROUD", "🏆", t("mood.PROUD")), ("THINKING_OF_YOU", "💭", t("mood.THINKING_OF_YOU")),
        ("NEED_A_HUG", "🤗", t("mood.NEED_A_HUG")), ("BUTTERFLIES", "🦋", t("mood.BUTTERFLIES")), ("TOUCHED", "🥹", t("mood.TOUCHED")),
        ("SAFE_WITH_YOU", "🫶", t("mood.SAFE_WITH_YOU")), ("BLISSFUL", "🌸", t("mood.BLISSFUL")), ("FLIRTY", "😏", t("mood.FLIRTY")),
        ("CONTENT", "☺️", t("mood.CONTENT")), ("DREAMY", "🌙", t("mood.DREAMY")),
        ("ANXIOUS", "😰", t("mood.ANXIOUS")), ("STRESSED", "🤯", t("mood.STRESSED")), ("ANGRY", "😤", t("mood.ANGRY")), ("LONELY", "🥀", t("mood.LONELY")),
        ("BORED", "🥱", t("mood.BORED")), ("SICK", "🤒", t("mood.SICK")), ("OVERWHELMED", "🌊", t("mood.OVERWHELMED")), ("HOMESICK", "🏡", t("mood.HOMESICK")),
        ].map { Mood(key: $0.0, emoji: $0.1, label: $0.2) }
    }

    public static let perPage = 8
    public static let limit = 48
    public static let labelMax = 16
    public static var labelRule: String { t("home.moodLabelRule") }
    public static var labelTaken: String { t("home.moodTaken") }

    /// "🌧️ Sad", or nil for no mood. An emoji and label from the API win over the code.
    public static func text(_ code: String?, emoji: String? = nil, label: String? = nil, catalogue: [Mood] = defaults) -> String? {
        guard let code else { return nil }
        if let emoji, !emoji.isEmpty, let label, !label.isEmpty { return "\(emoji) \(label)" }
        let mood = catalogue.first { $0.key == code } ?? defaults.first { $0.key == code }
        return mood.map { "\($0.emoji) \($0.label)" }
    }

    public static func normalise(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func labelLength(_ raw: String) -> Int {
        normalise(raw).unicodeScalars.count
    }

    /// Why `raw` can't be saved, or nil; empty is not reported (Save is simply off).
    public static func labelProblem(_ raw: String, catalogue: [Mood], exceptKey: String?) -> String? {
        let label = normalise(raw)
        if label.isEmpty { return nil }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.nonBaseCharacters)
            .union(CharacterSet(charactersIn: " .,!?'’&()-"))
        let hasLetterOrDigit = label.unicodeScalars.contains { CharacterSet.letters.union(.decimalDigits).contains($0) }
        if labelLength(label) > labelMax || !label.unicodeScalars.allSatisfy({ allowed.contains($0) }) || !hasLetterOrDigit {
            return labelRule
        }
        if catalogue.contains(where: { $0.key != exceptKey && $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
            return labelTaken
        }
        return nil
    }
}
