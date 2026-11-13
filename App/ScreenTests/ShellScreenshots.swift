import AppShell
import DLData
import DLDesignSystem
import DLI18n
import DLTestSupport
import DLUI
import FeatureDiscussions
import FeatureEmails
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

    @Test func startLanding() async {
        var state = signedOut
        state.entry = false
        await Shoot.screen(start(state: state), named: "start-landing-light", style: .light, wait: 1)
    }

    @Test func startLandingDark() async {
        var state = signedOut
        state.entry = false
        await Shoot.screen(start(state: state), named: "start-landing-dark", style: .dark, wait: 1)
    }

    @Test func startCards() async {
        await Shoot.screen(start(state: signedOut), named: "start-cards-light", style: .light, wait: 1.5)
    }

    @Test func startCardsDark() async {
        await Shoot.screen(start(state: signedOut), named: "start-cards-dark", style: .dark, wait: 1.5)
    }

    @Test func startPin() async {
        await Shoot.screen(start([.pin(userId: 1)], state: signedOut), named: "start-pin-light", style: .light, wait: 1.5)
    }

    @Test func startPinDark() async {
        await Shoot.screen(start([.pin(userId: 1)], state: signedOut), named: "start-pin-dark", style: .dark, wait: 1.5)
    }

    @Test func startCreate() async {
        var state = signedOut
        state.entry = false
        await Shoot.screen(start([.create], state: state), named: "start-create-light", style: .light, wait: 1)
    }

    @Test func startJoin() async {
        var state = signedOut
        state.entry = false
        await Shoot.screen(start([.join], state: state), named: "start-join-light", style: .light, wait: 1)
    }

    // MARK: Signed in

    // MARK: Home (canvas A-Home, A-Home-board, A-Home-empty, A-Home-waiting)

    @Test func homeLight() async {
        await Shoot.screen(app(.home, boardMini: true), named: "home-light", style: .light, wait: 2.5)
    }

    @Test func homeDark() async {
        await Shoot.screen(app(.home, theme: .dark, boardMini: true), named: "home-dark", style: .dark, wait: 2.5)
    }

    @Test func homeBoardLight() async {
        await Shoot.screen(app(.home), named: "home-board-light", style: .light, wait: 2.5)
    }

    @Test func homeBoardDark() async {
        await Shoot.screen(app(.home, theme: .dark), named: "home-board-dark", style: .dark, wait: 2.5)
    }

    @Test func homeEmpty() async {
        var state = FixtureServer.State()
        state.empty = true
        await Shoot.screen(app(.home, state: state), named: "home-empty-light", style: .light, wait: 2)
    }

    @Test func homeWaiting() async {
        var state = FixtureServer.State()
        state.alone = true
        state.empty = true
        await Shoot.screen(app(.home, state: state), named: "home-waiting-light", style: .light, wait: 2)
    }

    // MARK: Letters (canvas C-Letters, C-Letters-list, C-Letter-received, C-Letter-sent)

    @Test func lettersLight() async {
        await Shoot.screen(app(.letters), named: "letters-light", style: .light, wait: 2.5)
    }

    @Test func lettersDark() async {
        await Shoot.screen(app(.letters, theme: .dark), named: "letters-dark", style: .dark, wait: 2.5)
    }

    @Test func lettersList() async {
        let backend = FixtureBackend.make()
        backend.settings.setLettersList(true)
        await Shoot.screen(AppRoot(backend: backend, initialTab: .letters), named: "letters-list-light", style: .light, wait: 2.5)
    }

    private func letter(_ id: Int, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.home.start()
        return NavigationStack { LetterScreen(id: id) }
            .environment(backend)
            .environment(\.dlFirstCitizen, 1)
    }

    @Test func letterReceived() async {
        await Shoot.screen(letter(11), named: "letter-received-light", style: .light, wait: 2.5)
    }

    @Test func letterReceivedDark() async {
        await Shoot.screen(letter(11, theme: .dark), named: "letter-received-dark", style: .dark, wait: 2.5)
    }

    private func write(editId: Int? = nil, replyTo: Int? = nil, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.home.start()
        return NavigationStack { WriteScreen(editId: editId, replyTo: replyTo) }
            .environment(backend)
    }

    @Test func writeDraft() async {
        await Shoot.screen(write(), named: "write-draft-light", style: .light, wait: 2.5)
    }

    @Test func writeDraftDark() async {
        await Shoot.screen(write(theme: .dark), named: "write-draft-dark", style: .dark, wait: 2.5)
    }

    @Test func writeReply() async {
        await Shoot.screen(write(replyTo: 11), named: "write-reply-light", style: .light, wait: 2.5)
    }

    @Test func writeEdit() async {
        await Shoot.screen(write(editId: 21), named: "write-edit-light", style: .light, wait: 2.5)
    }

    @Test func letterSent() async {
        await Shoot.screen(letter(21), named: "letter-sent-light", style: .light, wait: 2.5)
    }

    // MARK: Discussions (canvas D-Discussions, D-Thread, D-Compose)

    @Test func discussionsLight() async {
        await Shoot.screen(app(.discussions), named: "discussions-light", style: .light, wait: 2.5)
    }

    @Test func discussionsDark() async {
        await Shoot.screen(app(.discussions, theme: .dark), named: "discussions-dark", style: .dark, wait: 2.5)
    }

    private func pushed<V: View>(_ view: V, theme: ThemeMode = .match) -> some View {
        let backend = FixtureBackend.make(theme: theme)
        backend.home.start()
        return NavigationStack { view }.environment(backend)
    }

    @Test func discussionThread() async {
        await Shoot.screen(pushed(DiscussionScreen(id: 31)), named: "discussion-thread-light", style: .light, wait: 2.5)
    }

    @Test func discussionCompose() async {
        await Shoot.screen(pushed(ComposeDiscussionScreen()), named: "discussion-compose-light", style: .light, wait: 2.5)
    }

    // MARK: Emails (canvas E-Emails, thread, new email)

    @Test func emailsLight() async {
        await Shoot.screen(app(.emails), named: "emails-light", style: .light, wait: 2.5)
    }

    @Test func emailsDark() async {
        await Shoot.screen(app(.emails, theme: .dark), named: "emails-dark", style: .dark, wait: 2.5)
    }

    @Test func emailThread() async {
        await Shoot.screen(pushed(ThreadScreen(id: 41)), named: "email-thread-light", style: .light, wait: 2.5)
    }

    @Test func newEmail() async {
        await Shoot.screen(pushed(NewEmailScreen()), named: "email-new-light", style: .light, wait: 2.5)
    }

    @Test func youLight() async {
        await Shoot.screen(app(.you), named: "you-light", style: .light, wait: 2)
    }

    @Test func youDark() async {
        await Shoot.screen(app(.you, theme: .dark), named: "you-dark", style: .dark, wait: 2)
    }

    @Test func appearanceLight() async {
        let backend = FixtureBackend.make()
        Shoot.screen(NavigationStack { AppearanceScreen(settings: backend.settings) }, named: "appearance-light", style: .light)
    }

    @Test func appearanceDark() async {
        let backend = FixtureBackend.make(theme: .dark)
        Shoot.screen(NavigationStack { AppearanceScreen(settings: backend.settings) }, named: "appearance-dark", style: .dark)
    }

    // MARK: Languages (doc "Delululand — Languages" L14: the Language screen and right-to-left samples)

    /// Renders in `lang`, then puts English back for the shots that follow.
    private func shoot(in lang: Lang, _ shot: () async -> Void) async {
        I18n.shared.set(lang)
        await shot()
        I18n.shared.set(.en)
    }

    @Test func languageLight() async {
        let backend = FixtureBackend.make()
        Shoot.screen(NavigationStack { LanguageScreen() }.environment(backend), named: "language-light", style: .light)
    }

    @Test func languageFaDark() async {
        await shoot(in: .fa) {
            let backend = FixtureBackend.make(theme: .dark)
            Shoot.screen(
                NavigationStack { LanguageScreen() }.environment(backend).environment(\.layoutDirection, .rightToLeft),
                named: "language-fa-dark", style: .dark
            )
        }
    }

    @Test func startCardsAz() async {
        await shoot(in: .az) {
            await Shoot.screen(start(state: signedOut), named: "start-cards-az-light", style: .light, wait: 1.5)
        }
    }

    @Test func startCardsFa() async {
        await shoot(in: .fa) {
            await Shoot.screen(start(state: signedOut).environment(\.layoutDirection, .rightToLeft), named: "start-cards-fa-light", style: .light, wait: 1.5)
        }
    }

    @Test func homeAz() async {
        await shoot(in: .az) {
            await Shoot.screen(app(.home), named: "home-az-light", style: .light, wait: 2.5)
        }
    }

    @Test func homeFa() async {
        await shoot(in: .fa) {
            await Shoot.screen(app(.home), named: "home-fa-light", style: .light, wait: 2.5)
        }
    }

    @Test func homeFaDark() async {
        await shoot(in: .fa) {
            await Shoot.screen(app(.home, theme: .dark), named: "home-fa-dark", style: .dark, wait: 2.5)
        }
    }

    @Test func lettersFa() async {
        await shoot(in: .fa) {
            await Shoot.screen(app(.letters), named: "letters-fa-light", style: .light, wait: 2.5)
        }
    }

    @Test func letterReceivedFa() async {
        await shoot(in: .fa) {
            await Shoot.screen(letter(11).environment(\.layoutDirection, .rightToLeft), named: "letter-received-fa-light", style: .light, wait: 2.5)
        }
    }

    @Test func youFa() async {
        await shoot(in: .fa) {
            await Shoot.screen(app(.you), named: "you-fa-light", style: .light, wait: 2)
        }
    }

    // L15–L23: Turkish and Russian — the 5-language list, the landing button, the tab bar's longest labels.

    @Test func languageRuLight() async {
        await shoot(in: .ru) {
            let backend = FixtureBackend.make()
            Shoot.screen(NavigationStack { LanguageScreen() }.environment(backend), named: "language-ru-light", style: .light)
        }
    }

    @Test func startCardsTr() async {
        await shoot(in: .tr) {
            await Shoot.screen(start(state: signedOut), named: "start-cards-tr-light", style: .light, wait: 1.5)
        }
    }

    @Test func startCardsRuDark() async {
        await shoot(in: .ru) {
            await Shoot.screen(start(state: signedOut), named: "start-cards-ru-dark", style: .dark, wait: 1.5)
        }
    }

    @Test func homeTr() async {
        await shoot(in: .tr) {
            await Shoot.screen(app(.home), named: "home-tr-light", style: .light, wait: 2.5)
        }
    }

    @Test func homeRu() async {
        await shoot(in: .ru) {
            await Shoot.screen(app(.home), named: "home-ru-light", style: .light, wait: 2.5)
        }
    }

    @Test func emailsRu() async {
        await shoot(in: .ru) {
            await Shoot.screen(app(.emails), named: "emails-ru-light", style: .light, wait: 2.5)
        }
    }

    @Test func youTr() async {
        await shoot(in: .tr) {
            await Shoot.screen(app(.you), named: "you-tr-light", style: .light, wait: 2)
        }
    }
}
