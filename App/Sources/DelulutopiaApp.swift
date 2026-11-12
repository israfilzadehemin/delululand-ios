import AppShell
import DLData
import DLDesignSystem
import SwiftUI

@main
struct DelulutopiaApp: App {
    @State private var settings = DeviceSettings()
    private let config = AppConfig.fromMainBundle()

    init() {
        DLFonts.register()
        DLAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(config: config, settings: settings)
        }
    }
}
