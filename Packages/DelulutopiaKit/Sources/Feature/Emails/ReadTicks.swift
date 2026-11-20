import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI

// Read ticks (doc "Delululand — Read Ticks" TK4–TK7; web emails/ticks.tsx): the glyphs after the
// time on my emails, and the delivery card above the quick row of the long-press layer.

/// ✓ (16 × 12 view box) or ✓✓ (20 × 12), the web's paths, stroked.
private struct TickShape: Shape {
    let double: Bool

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / (double ? 20 : 16)
        let sy = rect.height / 12
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        if double {
            path.move(to: p(1.5, 6.5)); path.addLine(to: p(4.7, 9.7)); path.addLine(to: p(12.5, 2))
            path.move(to: p(9.2, 9)); path.addLine(to: p(9.9, 9.7)); path.addLine(to: p(18, 2))
        } else {
            path.move(to: p(2.5, 6.5)); path.addLine(to: p(5.7, 9.7)); path.addLine(to: p(13.5, 2))
        }
        return path
    }
}

/// The glyph; the time beside it usually carries the words for VoiceOver.
struct ReadTicks: View {
    let status: TickStatus
    /// On a media chip: white, and read in a light blue that reads on the dark chip.
    var onMedia = false
    var tint: Color = .dlInkQuiet
    /// Spoken on its own (the list row); nil when the time beside it already says it.
    var label: String?

    var body: some View {
        let double = status != .sent
        let color: Color = status == .read
            ? (onMedia ? Color(red: 0x9F / 255, green: 0xD0 / 255, blue: 1) : .dlTickRead)
            : (onMedia ? .white : tint)
        TickShape(double: double)
            .stroke(color, style: StrokeStyle(lineWidth: 1.8 * (double ? 16.0 / 20 : 12.0 / 16), lineCap: .round, lineJoin: .round))
            .frame(width: double ? 16 : 12, height: 12)
            .accessibilityHidden(label == nil)
            .accessibilityLabel(label ?? "")
    }
}

/// TK6, TK7: Sent / Delivered / Read with their times on mine, Sent only on the friend's; glass like the menu.
struct DeliveryCard: View {
    let email: Email
    let mine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ReadTicksSpec.rows(email, mine: mine)) { row in
                HStack(spacing: 10) {
                    if mine { ReadTicks(status: row.status).frame(width: 20) }
                    Text(t(row.status.key)).font(.system(size: 13, weight: .bold)).foregroundStyle(.dlInk)
                    Spacer(minLength: 8)
                    Text(DLTime.clock(row.at)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.dlInkQuiet)
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.dlLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("emails.deliveryInfo"))
    }
}
