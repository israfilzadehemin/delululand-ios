import Foundation

/// The universe's video limits (doc "Delululand — Subscription Tiers" ST4, CM-6; web
/// src/media/limits.ts): Free 15 s / 100 MB, Premium 60 s / 400 MB. HomeStore sets them from Home's
/// plan; until then (or from an API before V24) the old 15 s / 100 MB hold.
public enum VideoLimits {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value = (seconds: 15, mb: 100)

    public static var seconds: Int { lock.withLock { value.seconds } }
    public static var mb: Int { lock.withLock { value.mb } }
    public static var maxBytes: Int { mb * 1024 * 1024 }

    public static func set(seconds: Int, mb: Int) {
        lock.withLock { value = (seconds, mb) }
    }
}
