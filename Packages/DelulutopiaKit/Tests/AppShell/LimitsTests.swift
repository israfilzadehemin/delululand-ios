import DLNetwork
@testable import DLUI
import Foundation
import Testing

/// Composer limits (doc "Delululand — Subscription Tiers" CM-1–CM-8; web src/plan/limits.test.ts).
@Suite("Subscription tier limits")
struct LimitsTests {
    private func free(photos: Int = 10, videos: Int = 3) -> Plan {
        Plan(
            tier: "free",
            limits: PlanLimits(emailsDaily: 100, photosPerMessage: 5, photosDaily: 10, videoSeconds: 15, videoMb: 100, videosDaily: 3, boardDoodlesDaily: 1),
            left: PlanLeft(emails: 100, photos: photos, videos: videos, boardDoodles: 1),
            renewsAt: "2026-11-17T00:00:00Z"
        )
    }

    @Test("Nothing is limited without a plan")
    func noPlan() {
        #expect(stripLimits(nil, MessageMedia(photos: 30)) == nil)
    }

    @Test("Quiet while plenty is left (ST16)")
    func quiet() throws {
        let l = try #require(stripLimits(free(), MessageMedia(photos: 2)))
        #expect(l.lines.isEmpty)
        #expect(l.block == nil)
        #expect(l.photoRoom == 3)
    }

    @Test("CM-1: the per-message limit")
    func perMessage() throws {
        let l = try #require(stripLimits(free(), MessageMedia(photos: 5)))
        #expect(l.photoRoom == 0)
        #expect(l.lines.first == .perMessage(5))
    }

    @Test("CM-7, CM-8: over-limit drafts are refused")
    func blocks() {
        #expect(stripLimits(free(), MessageMedia(photos: 7))?.block == .overMessage(n: 5, remove: 2))
        #expect(stripLimits(free(photos: 2), MessageMedia(photos: 3))?.block == .photosOver(left: 2, remove: 1))
        #expect(stripLimits(free(videos: 0), MessageMedia(photos: 0, videos: 1))?.block == .videosOver)
    }

    @Test("The plan decodes with an unlimited Board")
    func decodes() throws {
        let json = """
        {"tier":"premium","limits":{"emailsDaily":300,"photosPerMessage":10,"photosDaily":50,"videoSeconds":60,"videoMb":400,"videosDaily":10,"boardDoodlesDaily":null},
         "left":{"emails":300,"photos":50,"videos":10,"boardDoodles":null},"renewsAt":"2026-11-17T00:00:00Z"}
        """
        let plan = try JSONDecoder().decode(Plan.self, from: Data(json.utf8))
        #expect(plan.premium)
        #expect(plan.limits.boardDoodlesDaily == nil)
    }
}
