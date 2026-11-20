import DLNetwork

/// Earpiece Playback EP7 (doc "Delululand — Earpiece Playback"): which voice notes play on after one.
public enum VoiceRun {
    /// The voice notes of the emails after the one at `index` (oldest first, as the thread shows them)
    /// while they come from the same citizen and each carries a voice note. The run stops at the
    /// friend's email or one without a playable (unexpired, AR6) voice note.
    public static func after(_ emails: [Email], index: Int) -> [String] {
        guard emails.indices.contains(index) else { return [] }
        let sender = emails[index].senderId
        var out: [String] = []
        for e in emails[(index + 1)...] {
            guard e.senderId == sender else { break }
            let audios = e.attachments.filter { $0.kind == "audio" && !$0.expired }
            guard !audios.isEmpty else { break }
            out += audios.map(\.url)
        }
        return out
    }
}
