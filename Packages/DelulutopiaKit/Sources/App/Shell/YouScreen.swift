import DLData
import DLDesignSystem
import SwiftUI
import UIKit

enum YouRoute: Hashable {
    case appearance
    case designSystem
}

/// The You tab (iOS design F-You). PR #1 carries what works without signing in: Appearance, the
/// design-system page on staging builds, and the build's version and server. Profile, Universe,
/// Notifications, Face ID, Change PIN and Log out arrive in PR #2.
struct YouScreen: View {
    let config: AppConfig
    let settings: DeviceSettings

    var body: some View {
        List {
            Section {
                NavigationLink(value: YouRoute.appearance) {
                    DLRowLabel(
                        "Appearance",
                        subtitle: settings.themeMode.title,
                        icon: DLRowIcon("paintpalette.fill", tint: .dlSeal)
                    )
                }
                .dlListRow()
            }

            if config.isStaging {
                Section {
                    NavigationLink(value: YouRoute.designSystem) {
                        DLRowLabel(
                            "Design system",
                            subtitle: "Every component, light and dark",
                            icon: DLRowIcon("square.grid.2x2.fill", tint: .dlPostmarkHue)
                        )
                    }
                    .dlListRow()
                }
            }

            Section {
                aboutRow("Version", value: "\(config.version) (\(config.build))")
                aboutRow("Server", value: config.apiBaseURL.host() ?? config.apiBaseURL.absoluteString)
            } header: {
                DLSectionLabel("About")
            }
        }
        .dlGroupedList()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: YouRoute.self) { route in
            switch route {
            case .appearance:
                AppearanceScreen(settings: settings)
            case .designSystem:
                DLComponentCatalog()
                    .navigationTitle("Design system")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func aboutRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .dlText(.callout)
                .foregroundStyle(.dlInk)
            Spacer()
            Text(value)
                .dlText(.callout)
                .foregroundStyle(.dlInkQuiet)
        }
        .accessibilityElement(children: .combine)
        .dlListRow()
    }
}

/// Appearance (web S2): Light / Dark / Match device, saved on this device only.
struct AppearanceScreen: View {
    let settings: DeviceSettings

    var body: some View {
        List {
            Section {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        settings.setThemeMode(mode)
                    } label: {
                        DLCheckRow(mode.title, subtitle: mode.subtitle, checked: settings.themeMode == mode)
                    }
                    .buttonStyle(.plain)
                    .dlListRow()
                }
            } footer: {
                Text("Saved on this \(DeviceWord.current) only.")
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
            }
        }
        .dlGroupedList()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ThemeMode {
    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .match: "Match device"
        }
    }

    /// Web copy; "your phone or computer" becomes this device (iOS design §7).
    @MainActor
    var subtitle: String {
        switch self {
        case .light: "Paper and navy"
        case .dark: "Dusk paper, cream ink"
        case .match: "Follows this \(DeviceWord.current)"
        }
    }
}

/// "iPhone" or "iPad", for copy that names this device (iOS design §7: "This phone" → "This iPhone").
@MainActor
enum DeviceWord {
    static var current: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}
