import DLData
import DLDesignSystem
import DLNetwork
import SwiftUI

/// Writer colour key (web components/whoOf.ts): the universe's first citizen (lowest id) is "a"
/// (terracotta), the other "b" (sage). Until Home has loaded, user 1 is "a".
public enum Who: Sendable {
    case a, b

    public static func of(_ userId: Int?, first: Int?) -> Who {
        if let first { return userId == first ? .a : .b }
        return userId == 1 ? .a : .b
    }

    public var signature: Color { self == .a ? .dlUserA : .dlUserB }
    public var tint: Color { self == .a ? .dlUserATint : .dlUserBTint }
    public var avatar: DLAvatar.Signature { self == .a ? .a : .b }
}

public extension Home {
    /// The universe's first citizen, for `Who`.
    var firstCitizen: Int { min(me.id, friend?.id ?? me.id) }
}

/// P4: "Name Surname" initials, else the username's first letter.
public func initialsOf(_ nickname: String, firstName: String?, lastName: String?) -> String {
    let first = firstName?.trimmingCharacters(in: .whitespaces) ?? ""
    let last = lastName?.trimmingCharacters(in: .whitespaces) ?? ""
    if !first.isEmpty, !last.isEmpty { return (String(first.prefix(1)) + String(last.prefix(1))).uppercased() }
    if !first.isEmpty { return String(first.prefix(1)).uppercased() }
    return String(nickname.prefix(1)).uppercased()
}

public extension Citizen {
    var initials: String { initialsOf(nickname, firstName: firstName, lastName: lastName) }
    /// The current mood as it reads now (CM7): "🍵 Calm", or nil.
    var moodText: String? { Moods.text(mood, emoji: moodEmoji, label: moodLabel) }
}

/// "just now", "25 min ago", "2 h ago", "3 d ago".
public func ageWords(_ iso: String?, now: Date) -> String {
    guard let since = DLTime.date(iso) else { return "" }
    let s = max(0, Int(now.timeIntervalSince(since)))
    if s < 60 { return "just now" }
    let m = s / 60
    if m < 60 { return "\(m) min ago" }
    let h = m / 60
    if h < 24 { return "\(h) h ago" }
    return "\(h / 24) d ago"
}

/// A citizen's picture with the writer ring, from the universe colour key.
public struct CitizenAvatar: View {
    let citizen: Citizen
    let size: CGFloat
    @Environment(\.dlFirstCitizen) private var first

    public init(_ citizen: Citizen, size: CGFloat) {
        self.citizen = citizen
        self.size = size
    }

    public var body: some View {
        DLRemoteAvatar(
            url: citizen.avatarUrl,
            name: citizen.nickname,
            size: size,
            signature: Who.of(citizen.id, first: first).avatar,
            ring: true
        )
    }
}

/// A dashed rounded outline (the unset mood chip, the waiting card).
public struct DashedOutline: View {
    let color: Color
    let radius: CGFloat
    let width: CGFloat

    public init(_ color: Color, radius: CGFloat, width: CGFloat = 1) {
        self.color = color
        self.radius = radius
        self.width = width
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: [6, 4]))
    }
}

/// The offline line (UX S2 offline): shown over what was loaded last.
public struct OfflineBanner: View {
    @Environment(\.dlBrand) private var brand

    public init() {}

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.dlError)
            Text("Can’t reach \(brand). Showing what we had.")
                .dlText(.footnote)
                .foregroundStyle(.dlInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.dlErrorTint, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.dlErrorLine))
        .accessibilityElement(children: .combine)
        .dlEnter(.drop)
    }
}
