import AppShell
import DLData
import DLDesignSystem
import DLTestSupport
import DLUI
import FeatureDiscussions
import FeatureLetters
import FeatureStart
import Foundation
import SwiftUI
import Testing

/// The app on the fixture API (Emin and Leyla in Delulutopia), rendered on screen in the host app so
/// the system glass shows, and published to `ci-screenshots`.
@MainActor
@Suite("Shell screenshots", .serialized)
struct ShellScreenshots {
    private func app(_ tab: AppTab, theme: ThemeMode = .match, state: FixtureServer.State = .init(), boardMini: Bool = false) -> some View {
        AppRoot(backend: FixtureBackend.make(state: state, theme: theme, boardMini: boardMini), initialTab: tab)
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

    // MARK: Home (canvas A-Home, A-Home-board, A-Home-empty, A-Home-waiting)

    @Test func homeLight() {
        Shoot.screen(app(.home, boardMini: true), named: "home-light", style: .light, wait: 2.5)
    }

    @Test func homeDark() {
        Shoot.screen(app(.home, theme: .dark, boardMini: true), named: "home-dark", style: .dark, wait: 2.5)
    }

    @Test func homeBoardLight() {
        Shoot.screen(app(.home), named: "home-board-light", style: .light, wait: 2.5)
    }

    @Test func homeBoardDark() {
        Shoot.screen(app(.home, theme: .dark), named: "home-board-dark", style: .dark, wait: 2.5)
    }

    @Test func homeEmpty() {
        var state = FixtureServer.State()
        state.empty = true
        Shoot.screen(app(.home, state: state), named: "home-empty-light", style: .light, wait: 2)
    }

    @Test func homeWaiting() {
        var state = FixtureServer.State()
        state.alone = true
        state.empty = true
        Shoot.screen(app(.home, state: state), named: "home-waiting-light", style: .light, wait: 2)
    }

    // MARK: Letters (canvas C-Letters, C-Letters-list, C-Letter-received, C-Letter-sent)

    @Test func lettersLight() {
        Shoot.screen(app(.letters), named: "letters-light", style: .light, wait: 2.5)
    }

    @Test func lettersDark() {
        Shoot.screen(app(.letters, theme: .dark), named: "letters-dark", style: .dark, wait: 2.5)
    }

    @Test func lettersList() {
        let backend = FixtureBackend.make()
        backend.settings.setLettersList(true)
        Shoot.screen(AppRoot(backend: backend, initialTab: .letters), named: "letters-list-light", style: .light, wait: 2.5)
    }

    private func letter(_ id: Int, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.home.start()
        return NavigationStack { LetterScreen(id: id) }
            .environment(backend)
            .environment(\.dlFirstCitizen, 1)
    }

    @Test func letterReceived() {
        Shoot.screen(letter(11), named: "letter-received-light", style: .light, wait: 2.5)
    }

    @Test func letterReceivedDark() {
        Shoot.screen(letter(11, theme: .dark), named: "letter-received-dark", style: .dark, wait: 2.5)
    }

    private func write(editId: Int? = nil, replyTo: Int? = nil, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.home.start()
        return NavigationStack { WriteScreen(editId: editId, replyTo: replyTo) }
            .environment(backend)
    }

    @Test func writeDraft() {
        Shoot.screen(write(), named: "write-draft-light", style: .light, wait: 2.5)
    }

    @Test func writeDraftDark() {
        Shoot.screen(write(theme: .dark), named: "write-draft-dark", style: .dark, wait: 2.5)
    }

    @Test func writeReply() {
        Shoot.screen(write(replyTo: 11), named: "write-reply-light", style: .light, wait: 2.5)
    }

    @Test func writeEdit() {
        Shoot.screen(write(editId: 21), named: "write-edit-light", style: .light, wait: 2.5)
    }

    @Test func letterSent() {
        Shoot.screen(letter(21), named: "letter-sent-light", style: .light, wait: 2.5)
    }

    // MARK: Discussions (canvas D-Discussions, D-Thread, D-Compose)

    @Test func discussionsLight() {
        Shoot.screen(app(.discussions), named: "discussions-light", style: .light, wait: 2.5)
    }

    @Test func discussionsDark() {
        Shoot.screen(app(.discussions, theme: .dark), named: "discussions-dark", style: .dark, wait: 2.5)
    }

    private func pushed<V: View>(_ view: V, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.home.start()
        return NavigationStack { view }.environment(backend)
    }

    @Test func discussionThread() {
        Shoot.screen(pushed(DiscussionScreen(id: 31)), named: "discussion-thread-light", style: .light, wait: 2.5)
    }

    @Test func discussionCompose() {
        Shoot.screen(pushed(ComposeDiscussionScreen()), named: "discussion-compose-light", style: .light, wait: 2.5)
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
