import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import SwiftUI

/// YU-1, PL-2: a capsule, "Premium" (seal fill, star) or "Free" (outlined); 11 pt, heavy, caps.
public struct TierChip: View {
    let tier: String
    let large: Bool

    public init(_ tier: String, large: Bool = false) {
        self.tier = tier
        self.large = large
    }

    public var body: some View {
        let premium = tier == "premium"
        HStack(spacing: 5) {
            if premium { Image(systemName: "star").font(.system(size: 10, weight: .bold)) }
            Text((premium ? t("plan.premium") : t("plan.free")).uppercased(with: I18n.shared.lang.locale))
                .font(.system(size: 11, weight: .heavy))
                .tracking(11 * 0.08)
        }
        .foregroundStyle(premium ? Color.dlOnSeal : Color.dlInkQuiet)
        .padding(.leading, premium ? 8 : 10)
        .padding(.trailing, 10)
        .frame(height: large ? 26 : 22)
        .background {
            if premium {
                Capsule().fill(Color.dlSeal)
            } else {
                Capsule().strokeBorder(Color.dlInkQuiet, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Settings › Universe › Plan (doc "Delululand — Subscription Tiers" PL-1–PL-5; web
/// src/plan/PlanSection.tsx): the capsule in the header, allowance and what this citizen has left
/// today, the footer "Applies to both of you. Renews at 01:00." Read-only for both; no button (ST14).
public struct PlanSection: View {
    let tier: String
    let limits: PlanLimits
    let plan: Plan?

    public init(tier: String, limits: PlanLimits, plan: Plan?) {
        self.tier = tier
        self.limits = limits
        self.plan = plan
    }

    private struct PlanRow: Identifiable {
        let label: String
        let allowance: String
        /// nil: no Today cell; -1: "—" (unlimited).
        let today: Int?
        var id: String { label }
    }

    public var body: some View {
        let left = plan?.left
        let rows = [
            PlanRow(label: t("plan.emails"), allowance: t("plan.perDay", ["n": limits.emailsDaily]), today: left?.emails),
            PlanRow(
                label: t("plan.photos"),
                allowance: t("plan.perMessage", ["n": limits.photosPerMessage, "daily": limits.photosDaily]),
                today: left?.photos
            ),
            PlanRow(
                label: t("plan.videos"),
                allowance: t("plan.videoEach", ["seconds": limits.videoSeconds, "daily": limits.videosDaily]),
                today: left?.videos
            ),
            PlanRow(
                label: t("plan.boardDoodles"),
                allowance: limits.boardDoodlesDaily.map { t("plan.perDay", ["n": $0]) } ?? t("plan.unlimited"),
                today: limits.boardDoodlesDaily == nil ? (left == nil ? nil : -1) : left?.boardDoodles
            ),
        ]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DLSectionLabel(t("plan.title"))
                Spacer()
                TierChip(tier, large: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(Color.dlLine) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label).dlText(.subheadlineBold).foregroundStyle(.dlInk)
                            Text(row.allowance).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        }
                        Spacer()
                        if let today = row.today {
                            Text(today < 0 ? "—" : today == 0 ? t("plan.noneLeft") : t("plan.left", ["n": today]))
                                .dlText(.subheadlineBold)
                                .monospacedDigit()
                                .foregroundStyle(today == 0 ? Color.dlError : Color.dlInk)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.dlCell, in: RoundedRectangle(cornerRadius: 12))
            Text(footer).dlText(.footnote).foregroundStyle(.dlInkQuiet)
        }
    }

    private var footer: String {
        guard let plan else { return t("plan.both") }
        return t("plan.both") + " " + t("plan.renews", ["time": DLTime.time(plan.renewsAt)]) + "."
    }
}
