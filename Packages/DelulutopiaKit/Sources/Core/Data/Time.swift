import DLNetwork
import Foundation

/// Instants and clock text (web `src/clock`; Android `Time`): the viewer's zone, 24-hour, en-GB.
public enum DLTime {
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func formatter(_ format: String, zone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    /// Server-aligned now (`X-Server-Time`).
    public static var now: Date { ServerClock.shared.now }

    public static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return isoFractional.date(from: iso) ?? isoPlain.date(from: iso)
    }

    public static func iso(_ date: Date) -> String {
        isoFractional.string(from: date)
    }

    /// FS-T6: `HH:MM` today; `27 Oct, 21:10` another day this year; `27 Oct 2025, 21:10` in another year.
    public static func clock(_ iso: String?, now: Date = DLTime.now) -> String {
        guard let d = date(iso) else { return "" }
        let cal = Calendar.current
        let time = formatter("HH:mm").string(from: d)
        if cal.isDate(d, inSameDayAs: now) { return time }
        if cal.component(.year, from: d) == cal.component(.year, from: now) {
            return "\(formatter("d MMM").string(from: d)), \(time)"
        }
        return "\(formatter("d MMM yyyy").string(from: d)), \(time)"
    }

    /// `HH:MM` only.
    public static func time(_ iso: String?) -> String {
        date(iso).map { formatter("HH:mm").string(from: $0) } ?? ""
    }

    public static func time(of date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    /// A day without the time: `10 Nov` this year, `10 Nov 2025` in another.
    public static func day(_ iso: String?, now: Date = DLTime.now) -> String {
        guard let d = date(iso) else { return "" }
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: now)
        return formatter(sameYear ? "d MMM" : "d MMM yyyy").string(from: d)
    }

    /// m:ss for a remaining duration; never negative; hours never appear (28:41).
    public static func countdown(_ remaining: TimeInterval) -> String {
        let total = Int((max(remaining, 0)).rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// The remaining time until `iso`.
    public static func remaining(until iso: String?, now: Date = DLTime.now) -> TimeInterval {
        guard let d = date(iso) else { return 0 }
        return d.timeIntervalSince(now)
    }

    /// `PT1H` → 3600, `PT6M` → 360, `PT30S` → 30.
    public static func isoDuration(_ iso: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: #"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#),
              let match = regex.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) else { return nil }
        func group(_ i: Int) -> Double {
            guard let range = Range(match.range(at: i), in: iso) else { return 0 }
            return Double(iso[range]) ?? 0
        }
        return group(1) * 3600 + group(2) * 60 + group(3)
    }

    /// `m:ss` of a duration, for the TEST banner ("DELAY 6:00 · WINDOW 0:30").
    public static func durationText(_ iso: String) -> String {
        guard let seconds = isoDuration(iso) else { return iso }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Hour (0–23) and minute on the wall clock of `zone`; unknown zones read as UTC.
    public static func wallClock(_ now: Date, zone: String) -> (hour: Int, minute: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone) ?? TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    public static func city(of zone: String) -> String {
        (zone.split(separator: "/").last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ")
    }

    public static func isNight(hour: Int) -> Bool { hour >= 22 || hour < 7 }

    /// "m:ss" of a media duration in milliseconds (voice notes, videos).
    public static func mediaLength(ms: Int?) -> String {
        let total = Int((Double(ms ?? 0) / 1000).rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

/// Letter and discussion states (Technical Design §3.2): the server's answer is authoritative; this
/// flips the UI at 0:00.
public enum LetterState {
    public static let inReach = "IN_REACH"
    public static let inTransit = "IN_TRANSIT"
    public static let delivered = "DELIVERED"
    public static let read = "READ"
    public static let arrived = "ARRIVED"

    public static func of(now: Date, windowEndsAt: String, arrivesAt: String, readAt: String?) -> String {
        if readAt != nil { return read }
        if now >= (DLTime.date(arrivesAt) ?? .distantPast) { return delivered }
        if now >= (DLTime.date(windowEndsAt) ?? .distantPast) { return inTransit }
        return inReach
    }

    public static func of(_ row: LetterRow, now: Date) -> String {
        of(now: now, windowEndsAt: row.windowEndsAt, arrivesAt: row.arrivesAt, readAt: row.readAt)
    }

    /// Discussions have no Read state (Discussions §2).
    public static func discussion(now: Date, windowEndsAt: String, arrivesAt: String) -> String {
        if now >= (DLTime.date(arrivesAt) ?? .distantPast) { return arrived }
        if now >= (DLTime.date(windowEndsAt) ?? .distantPast) { return inTransit }
        return inReach
    }
}
