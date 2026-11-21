import AppShell
import DLData
import DLDesignSystem
import DLI18n
import DLTestSupport
import DLUI
import FeatureLetters
import Foundation
import SwiftUI
import Testing
import UIKit

/// The iPad split on a 13″ iPad simulator, landscape and portrait (doc "Delululand — iPad Layout"
/// §7, IP15: the App Store's 13″ set comes from these). Runs only in the iPad screenshot run.
@MainActor
@Suite("iPad screenshots", .serialized, .enabled(if: Shoot.onIPad))
struct IPadScreenshots {
    /// The app on the fixture API, opened on `tab` or at `link` (a notification tap's path).
    private func app(_ tab: AppTab, link: AppLink? = nil, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.push.pendingLink = link
        return AppRoot(backend: backend, initialTab: tab)
    }

    /// iPad Pro 13-inch in points: the App Store's 13″ shots are 2752 × 2064 px at 2× (IP15).
    static func size(landscape: Bool) -> CGSize {
        landscape ? CGSize(width: 1376, height: 1032) : CGSize(width: 1032, height: 1376)
    }

    private func shoot(_ tab: AppTab, link: AppLink? = nil, _ name: String) async {
        for landscape in [true, false] {
            let o = landscape ? "landscape" : "portrait"
            await Shoot.device(app(tab, link: link), named: "ipad-\(name)-\(o)-light", style: .light, wait: 3, landscape: landscape, size: Self.size(landscape: landscape))
            await Shoot.device(app(tab, link: link, theme: .dark), named: "ipad-\(name)-\(o)-dark", style: .dark, wait: 3, landscape: landscape, size: Self.size(landscape: landscape))
            I18n.shared.set(.fa)
            await Shoot.device(app(tab, link: link), named: "ipad-\(name)-\(o)-fa-light", style: .light, wait: 3, landscape: landscape, size: Self.size(landscape: landscape))
            I18n.shared.set(.en)
        }
    }

    @Test func home() async { await shoot(.home, "home") }
    @Test func letter() async { await shoot(.letters, link: .letter("11"), "letter") }
    @Test func discussion() async { await shoot(.discussions, link: .discussion("31"), "discussion") }
    @Test func thread() async { await shoot(.emails, link: .thread("41"), "thread") }
    @Test func you() async { await shoot(.you, "you") }

    /// IP4: nothing selected shows the hint, nothing is opened by itself.
    @Test func lettersHint() async {
        await Shoot.device(app(.letters), named: "ipad-letters-hint-landscape-light", style: .light, wait: 3, landscape: true, size: Self.size(landscape: true))
    }

    /// IP6: Write as a full-screen cover, the answered letter beside the sheet (canvas T-Write).
    @Test func writeReply() async {
        let backend = FixtureBackend.make()
        backend.home.start()
        let view = NavigationStack { WriteScreen(replyTo: "11") }
            .environment(backend)
            .environment(\.dlLayout, .split)
            .environment(\.dlClose) {}
        await Shoot.device(view, named: "ipad-write-reply-landscape-light", style: .light, wait: 3, landscape: true, size: Self.size(landscape: true))
    }
}

/// The iPhone Duo's unfolded display (iPad Layout IP10, IP12): iPhone navigation with wide layouts.
/// The runner's iPhone Duo simulator has two displays: the inner one is 2007 × 2853 px (≈ 951 × 669 pt
/// turned, at 3×; the canvas assumed ≈ 1010 × 716) and the cover 1398 × 2034 px. The shots are drawn at
/// the inner display's size on the iPhone run.
@MainActor
@Suite("Duo screenshots", .serialized, .enabled(if: !Shoot.onIPad))
struct DuoScreenshots {
    static let canvas = CGSize(width: 951, height: 669)

    private func app(_ tab: AppTab, link: AppLink? = nil, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.push.pendingLink = link
        return AppRoot(backend: backend, initialTab: tab, layout: .widePhone)
    }

    private func shot(_ view: some View, _ name: String, _ style: UIUserInterfaceStyle) async {
        await Shoot.device(view, named: name, style: style, wait: 3, landscape: true, size: Self.canvas)
    }

    private func shoot(_ tab: AppTab, link: AppLink? = nil, _ name: String) async {
        await shot(app(tab, link: link), "duo-\(name)-light", .light)
        await shot(app(tab, link: link, theme: .dark), "duo-\(name)-dark", .dark)
        I18n.shared.set(.fa)
        await shot(app(tab, link: link), "duo-\(name)-fa-light", .light)
        I18n.shared.set(.en)
    }

    @Test func home() async { await shoot(.home, "home") }
    @Test func letters() async { await shoot(.letters, "letters") }
    @Test func letter() async { await shoot(.letters, link: .letter("11"), "letter") }
    @Test func thread() async { await shoot(.emails, link: .thread("41"), "thread") }
}
