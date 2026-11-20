import DLNetwork

/// Read ticks (doc "Delululand — Read Ticks" TK5–TK7; web emails/ticks.tsx, Android ReadTicks.kt): the
/// state of one of my emails, and the rows of the delivery card in the long-press layer.
public enum TickStatus: String, Sendable, CaseIterable {
    case sent, delivered, read

    /// Read implies delivered, so the latest mark wins.
    public static func of(_ e: Email) -> TickStatus {
        if e.readAt != nil { return .read }
        if e.deliveredAt != nil { return .delivered }
        return .sent
    }

    /// `ThreadRow.lastStatus` (TK10); nil for anything else.
    public static func of(wire: String?) -> TickStatus? {
        wire.flatMap(TickStatus.init(rawValue:))
    }

    /// `emails.status.sent` etc.
    public var key: String { "emails.status.\(rawValue)" }
    /// "14:16, read" for VoiceOver: `emails.status.readLabel` etc.
    public var labelKey: String { "emails.status.\(rawValue)Label" }
}

/// One row of the delivery card: a state and when it happened.
public struct DeliveryRow: Sendable, Hashable, Identifiable {
    public let status: TickStatus
    public let at: String
    public var id: TickStatus { status }
}

public enum ReadTicksSpec {
    /// TK6, TK7: mine list every state reached with its time; the friend's show Sent only.
    public static func rows(_ e: Email, mine: Bool) -> [DeliveryRow] {
        var out = [DeliveryRow(status: .sent, at: e.sentAt)]
        guard mine else { return out }
        if let d = e.deliveredAt { out.append(DeliveryRow(status: .delivered, at: d)) }
        if let r = e.readAt { out.append(DeliveryRow(status: .read, at: r)) }
        return out
    }
}
