import AppShell
import DLData
import DLDesignSystem
import DLTestSupport
import FeatureStart
import Foundation
import SwiftUI
import Testing

/// The app on the fixture API (Emin and Leyla in Delulutopia), rendered on screen in the host app so
/// the system glass shows, and published to `ci-screenshots`.
@MainActor
@Suite("Shell screenshots", .serialized)
struct ShellScreenshots {
    private func app(_ tab: AppTab, theme: ThemeMode = .match, state: FixtureServer.State = .init()) -> some View {
        AppRoot(backend: FixtureBackend.make(state: state, theme: theme), initialTab: tab)
    }

    private func start(_ path: [StartRoute] = [], state: FixtureServer.State) -> some View {
        let backend = FixtureBackend.make(state: state)
        return StartFlow(path: path).environment(backend)
    }

    private var signedOut: FixtureServer.State {
        var state = FixtureServer.State()
        state.auth = false
        return state
    }

    // MARK: Start

    @Test func startLanding() {
        var state = signedOut
        state.entry = false
        Shoot.screen(start(state: state), named: "start-landing-light", style: .light, wait: 1)
    }

    @Test func startLandingDark() {
        var state = signedOut
        state.entry = false
        Shoot.screen(start(state: state), named: "start-landing-dark", style: .dark, wait: 1)
    }

    @Test func startCards() {
        Shoot.screen(start(state: signedOut), named: "start-cards-light", style: .light, wait: 1.5)
    }

    @Test func startCardsDark() {
        Shoot.screen(start(state: signedOut), named: "start-cards-dark", style: .dark, wait: 1.5)
    }

    @Test func startPin() {
        Shoot.screen(start([.pin(userId: 1)], state: signedOut), named: "start-pin-light", style: .light, wait: 1.5)
    }

    @Test func startPinDark() {
        Shoot.screen(start([.pin(userId: 1)], state: signedOut), named: "start-pin-dark", style: .dark, wait: 1.5)
    }

    @Test func startCreate() {
        var state = signedOut
        state.entry = false
        Shoot.screen(start([.create], state: state), named: "start-create-light", style: .light, wait: 1)
    }

    @Test func startJoin() {
        var state = signedOut
        state.entry = false
        Shoot.screen(start([.join], state: state), named: "start-join-light", style: .light, wait: 1)
    }

    // MARK: Signed in

    @Test func homeLight() {
        Shoot.screen(app(.home), named: "home-light", style: .light, wait: 2)
    }

    @Test func homeDark() {
        Shoot.screen(app(.home, theme: .dark), named: "home-dark", style: .dark, wait: 2)
    }

    @Test func lettersLight() {
        Shoot.screen(app(.letters), named: "letters-light", style: .light, wait: 2)
    }

    @Test func youLight() {
        Shoot.screen(app(.you), named: "you-light", style: .light, wait: 2)
    }

    @Test func youDark() {
        Shoot.screen(app(.you, theme: .dark), named: "you-dark", style: .dark, wait: 2)
    }

    @Test func appearanceLight() {
        let backend = FixtureBackend.make()
        Shoot.screen(NavigationStack { AppearanceScreen(settings: backend.settings) }, named: "appearance-light", style: .light)
    }

    @Test func appearanceDark() {
        let backend = FixtureBackend.make(theme: .dark)
        Shoot.screen(NavigationStack { AppearanceScreen(settings: backend.settings) }, named: "appearance-dark", style: .dark)
    }
}
