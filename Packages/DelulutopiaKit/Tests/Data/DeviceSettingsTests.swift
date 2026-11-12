@testable import DLData
import Foundation
import Testing

@MainActor
@Suite("Device settings")
struct DeviceSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "dl.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A new device follows the device appearance")
    func defaultsToMatch() {
        #expect(DeviceSettings(defaults: freshDefaults()).themeMode == .match)
    }

    @Test("A chosen theme is kept for the next launch")
    func persists() {
        let defaults = freshDefaults()
        DeviceSettings(defaults: defaults).setThemeMode(.dark)
        #expect(DeviceSettings(defaults: defaults).themeMode == .dark)
    }

    @Test("Match device forgets the stored choice")
    func matchForgets() {
        let defaults = freshDefaults()
        let settings = DeviceSettings(defaults: defaults)
        settings.setThemeMode(.light)
        settings.setThemeMode(.match)
        #expect(defaults.string(forKey: DeviceSettings.Keys.theme) == nil)
        #expect(DeviceSettings(defaults: defaults).themeMode == .match)
    }

    @Test("An unknown stored value falls back to Match device")
    func unknownValue() {
        let defaults = freshDefaults()
        defaults.set("sepia", forKey: DeviceSettings.Keys.theme)
        #expect(DeviceSettings(defaults: defaults).themeMode == .match)
    }
}

@Suite("App config")
struct AppConfigTests {
    @Test("Staging and prod read from the Info.plist values the xcconfigs set")
    func readsEnvironments() {
        let staging = AppConfig(info: [
            "DLEnvironment": "staging",
            "DLApiBaseURL": "https://test.delulutopia.com",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "7",
        ])
        #expect(staging.environment == .staging)
        #expect(staging.apiBaseURL.absoluteString == "https://test.delulutopia.com")
        #expect(staging.version == "0.1.0")
        #expect(staging.build == "7")
        #expect(staging.isStaging)

        let prod = AppConfig(info: ["DLEnvironment": "prod", "DLApiBaseURL": "https://delulutopia.com"])
        #expect(prod.environment == .prod)
        #expect(prod.apiBaseURL.host() == "delulutopia.com")
        #expect(!prod.isStaging)
    }

    @Test("A missing or non-HTTPS server never falls back to production")
    func fallsBackToStaging() {
        let missing = AppConfig(info: ["DLEnvironment": "prod"])
        #expect(missing.environment == .staging)
        #expect(missing.apiBaseURL == AppConfig.stagingURL)

        let plain = AppConfig(info: ["DLEnvironment": "prod", "DLApiBaseURL": "http://delulutopia.com"])
        #expect(plain.environment == .staging)
        #expect(plain.apiBaseURL == AppConfig.stagingURL)

        let unresolved = AppConfig(info: ["DLApiBaseURL": "$(DL_API_BASE_URL)"])
        #expect(unresolved.apiBaseURL == AppConfig.stagingURL)
    }
}
