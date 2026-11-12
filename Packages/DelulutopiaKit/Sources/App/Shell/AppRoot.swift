import DLData
import DLDesignSystem
import SwiftUI

/// The five destinations of the floating tab bar (iOS design §3): Home · Letters · Discussions ·
/// Emails · You (the citizen's picture).
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case letters
    case discussions
    case emails
    case you

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .letters: "Letters"
        case .discussions: "Discussions"
        case .emails: "Emails"
        case .you: "You"
        }
    }

    /// The line a placeholder tab shows until its screen lands (PR #2).
    var placeholderLine: String {
        switch self {
        case .home: "Home arrives in the next build."
        case .you: "You arrives in the next build."
        default: "\(title) arrive in the next build."
        }
    }

    /// SF Symbols from the canvas "Foundations › SF Symbols" (You draws the picture instead).
    var symbol: String {
        switch self {
        case .home: "house"
        case .letters: "envelope"
        case .discussions: "bubble.left.and.bubble.right"
        case .emails: "at"
        case .you: "person.crop.circle"
        }
    }
}

/// The app's root: theme, tint and the tab bar. Signing in, live updates and the screens behind the
/// tabs arrive in PR #2.
public struct AppRoot: View {
    let config: AppConfig
    let settings: DeviceSettings
    @State private var selection: AppTab

    public init(config: AppConfig, settings: DeviceSettings, initialTab: AppTab = .home) {
        self.config = config
        self.settings = settings
        self._selection = State(initialValue: initialTab)
    }

    public var body: some View {
        MainTabView(selection: $selection, config: config, settings: settings)
            .tint(.dlSeal)
            .preferredColorScheme(settings.themeMode.colorScheme)
    }
}

extension ThemeMode {
    /// Nil follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .match: nil
        }
    }
}
