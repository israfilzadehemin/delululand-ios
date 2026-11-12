@testable import AppShell
import DLData
import Testing

@Suite("Shell")
struct ShellTests {
    @Test("Five tabs in the design's order")
    func tabs() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Letters", "Discussions", "Emails", "You"])
    }

    @Test("Theme modes map to the window style; Match device follows the device")
    func themeModes() {
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
        #expect(ThemeMode.match.colorScheme == nil)
    }
}
