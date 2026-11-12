import Foundation
import Observation

/// The in-app theme choice (web `ThemeChoice`: light / dark / match). It overrides the window style
/// and is saved per device (iOS design I-11).
public enum ThemeMode: String, CaseIterable, Sendable, Identifiable {
    case light
    case dark
    case match

    public var id: String { rawValue }
}

/// Settings that belong to this device rather than to the citizen (Android `DeviceSettingsRepository`).
@MainActor
@Observable
public final class DeviceSettings {
    enum Keys {
        static let theme = "dl.theme"
    }

    private let defaults: UserDefaults

    public private(set) var themeMode: ThemeMode

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.themeMode = defaults.string(forKey: Keys.theme).flatMap(ThemeMode.init(rawValue:)) ?? .match
    }

    /// Match device forgets the stored choice (web: "Match device forgets the stored choice").
    public func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        if mode == .match {
            defaults.removeObject(forKey: Keys.theme)
        } else {
            defaults.set(mode.rawValue, forKey: Keys.theme)
        }
    }
}
