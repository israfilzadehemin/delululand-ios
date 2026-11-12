import AppShell
import DLData
import DLDesignSystem
import SwiftUI

@main
struct DelulutopiaApp: App {
    @State private var settings = DeviceSettings()
    private let config = AppConfig.fromMainBundle()
    /// The app hosts the screenshot tests (DelulutopiaScreens); they draw their own screens.
    private let hostsTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        DLFonts.register()
        DLAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            if hostsTests {
                Color.clear
            } else {
                AppRoot(config: config, settings: settings)
            }
        }
    }
}
