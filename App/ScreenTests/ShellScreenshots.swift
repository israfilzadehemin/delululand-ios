import AppShell
import DLData
import DLDesignSystem
import DLTestSupport
import Foundation
import SwiftUI
import Testing

/// The app shell (tab bar, You, Appearance) in light and dark, rendered on screen in the host app so
/// the system glass shows, and published to `ci-screenshots`.
@MainActor
@Suite("Shell screenshots", .serialized)
struct ShellScreenshots {
    private let config = AppConfig(
        environment: .staging,
        apiBaseURL: URL(string: "https://test.delulutopia.com")!,
        version: "0.1.0",
        build: "1"
    )

    private func makeSettings(_ mode: ThemeMode = .match) -> DeviceSettings {
        let name = "dl.shots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = DeviceSettings(defaults: defaults)
        settings.setThemeMode(mode)
        return settings
    }

    @Test func homeLight() {
        Shoot.screen(AppRoot(config: config, settings: makeSettings(), initialTab: .home), named: "home-light", style: .light)
    }

    @Test func homeDark() {
        Shoot.screen(AppRoot(config: config, settings: makeSettings(), initialTab: .home), named: "home-dark", style: .dark)
    }

    @Test func lettersLight() {
        Shoot.screen(AppRoot(config: config, settings: makeSettings(), initialTab: .letters), named: "letters-light", style: .light)
    }

    @Test func youLight() {
        Shoot.screen(AppRoot(config: config, settings: makeSettings(), initialTab: .you), named: "you-light", style: .light)
    }

    @Test func youDark() {
        Shoot.screen(AppRoot(config: config, settings: makeSettings(), initialTab: .you), named: "you-dark", style: .dark)
    }

    @Test func appearanceLight() {
        Shoot.screen(NavigationStack { AppearanceScreen(settings: makeSettings()) }, named: "appearance-light", style: .light)
    }

    @Test func appearanceDark() {
        Shoot.screen(NavigationStack { AppearanceScreen(settings: makeSettings(.dark)) }, named: "appearance-dark", style: .dark)
    }
}
