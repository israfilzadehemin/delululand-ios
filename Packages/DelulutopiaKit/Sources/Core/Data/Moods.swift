import DLNetwork
import Foundation

/// Moods (web `src/text/moods.ts`, doc "Delululand — Moods"). The API's catalogue is the source; these
/// show while it loads.
public enum Moods {
    public static let defaults: [Mood] = [
        ("HAPPY", "😊", "Happy"), ("CALM", "🍵", "Calm"), ("CURIOUS", "🤔", "Curious"), ("INSPIRED", "✨", "Inspired"),
        ("BUSY", "🏃", "Busy"), ("TIRED", "😴", "Tired"), ("SAD", "🌧️", "Sad"), ("MISSING_YOU", "💌", "Missing you"),
        ("LOVED", "🥰", "Loved"), ("GRATEFUL", "🙏", "Grateful"), ("EXCITED", "🤩", "Excited"), ("PLAYFUL", "😜", "Playful"),
        ("COZY", "🧸", "Cozy"), ("HOPEFUL", "🌱", "Hopeful"), ("PROUD", "🏆", "Proud"), ("THINKING_OF_YOU", "💭", "Thinking of you"),
        ("NEED_A_HUG", "🤗", "Need a hug"), ("BUTTERFLIES", "🦋", "Butterflies"), ("TOUCHED", "🥹", "Touched"),
        ("SAFE_WITH_YOU", "🫶", "Safe with you"), ("BLISSFUL", "🌸", "Blissful"), ("FLIRTY", "😏", "Flirty"),
        ("CONTENT", "☺️", "Content"), ("DREAMY", "🌙", "Dreamy"),
        ("ANXIOUS", "😰", "Anxious"), ("STRESSED", "🤯", "Stressed"), ("ANGRY", "😤", "Angry"), ("LONELY", "🥀", "Lonely"),
        ("BORED", "🥱", "Bored"), ("SICK", "🤒", "Sick"), ("OVERWHELMED", "🌊", "Overwhelmed"), ("HOMESICK", "🏡", "Homesick"),
    ].map { Mood(key: $0.0, emoji: $0.1, label: $0.2) }

    public static let perPage = 8
    public static let limit = 48
    public static let labelMax = 16
    public static let labelRule = "Up to 16 letters, digits or simple punctuation"
    public static let labelTaken = "That mood already exists."

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
