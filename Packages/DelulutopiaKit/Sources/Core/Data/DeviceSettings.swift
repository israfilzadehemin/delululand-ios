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
        static let boardMini = "dl.boardMini"
        static let lettersList = "dl.lettersList"
        static let leaves = "dl.leaves"
        static let recentEmojis = "dl.recentEmojis"
        static let notifyAsked = "dl.notifyAsked"
        static let faceIDOffered = "dl.faceIDOffered"
    }

    private let defaults: UserDefaults

    public private(set) var themeMode: ThemeMode
    /// Board §9: the Home tile folded to a strip.
    public private(set) var boardMini: Bool
    /// Letters: the compact list instead of the tile grid (thumbnails are the default).
    public private(set) var lettersList: Bool
    /// Falling leaves over Home and the lists (Appearance › Seasonal effects).
    public private(set) var leaves: Bool
    /// Reactions: the emojis picked last, newest first (web `reactions/recents.ts`).
    public private(set) var recentEmojis: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.themeMode = defaults.string(forKey: Keys.theme).flatMap(ThemeMode.init(rawValue:)) ?? .match
        self.boardMini = defaults.bool(forKey: Keys.boardMini)
        self.lettersList = defaults.bool(forKey: Keys.lettersList)
        self.leaves = defaults.object(forKey: Keys.leaves) as? Bool ?? true
        self.recentEmojis = defaults.stringArray(forKey: Keys.recentEmojis) ?? []
    }

    public func setBoardMini(_ mini: Bool) {
        boardMini = mini
        defaults.set(mini, forKey: Keys.boardMini)
    }

    public func setLettersList(_ list: Bool) {
        lettersList = list
        defaults.set(list, forKey: Keys.lettersList)
    }

    public func setLeaves(_ on: Bool) {
        leaves = on
        defaults.set(on, forKey: Keys.leaves)
    }

    public func pushRecentEmoji(_ emoji: String, keep: Int = 8) {
        recentEmojis = Array(([emoji] + recentEmojis.filter { $0 != emoji }).prefix(keep))
        defaults.set(recentEmojis, forKey: Keys.recentEmojis)
    }

    /// Whether the notification ask after a PIN entry was answered on this device.
    public var notifyAsked: Bool {
        get { defaults.bool(forKey: Keys.notifyAsked) }
        set { defaults.set(newValue, forKey: Keys.notifyAsked) }
    }

    /// Whether "Unlock with Face ID?" was offered on this device (offered once after a PIN entry).
    public var faceIDOffered: Bool {
        get { defaults.bool(forKey: Keys.faceIDOffered) }
        set { defaults.set(newValue, forKey: Keys.faceIDOffered) }
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
