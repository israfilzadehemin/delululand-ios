import AppShell
import DLData
import DLDesignSystem
import SwiftUI

@main
struct DelulutopiaApp: App {
    @State private var backend = Backend(config: AppConfig.fromMainBundle(), settings: DeviceSettings())
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
                AppRoot(backend: backend)
            }
        }
    }
}
