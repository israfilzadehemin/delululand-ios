import DLData
import DLDesignSystem
import DLNetwork
import SwiftUI

/// Places a screen can open, whichever tab it lives in (the Android `AppNav` routes). The shell
/// pushes them on the current tab's stack and maps each to its screen.
public enum AppRoute: Hashable, Sendable {
    case letter(Int)
    case write(editId: Int? = nil, replyTo: Int? = nil)
    case discussion(Int)
    case composeDiscussion(editId: Int?)
    case thread(Int)
    case newEmail
    case friend
    case profile
    case universe
    case appearance
    case notifications
}

/// The tabs, for opening one from anywhere (a toast, an arrival notice, a notification).
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home, letters, discussions, emails, you

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .letters: "Letters"
        case .discussions: "Discussions"
        case .emails: "Emails"
        case .you: "You"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house"
        case .letters: "envelope"
        case .discussions: "bubble.left.and.bubble.right"
        case .emails: "at"
        case .you: "person.crop.circle"
        }
    }
}

public extension EnvironmentValues {
    /// Opens a route on the current tab's stack.
    @Entry var dlOpen: @MainActor (AppRoute) -> Void = { _ in }
    /// Switches tab (and pops it to its root when `root` is set).
    @Entry var dlSelectTab: @MainActor (AppTab) -> Void = { _ in }
    /// Shows a toast above the tab bar.
    @Entry var dlNotice: @MainActor (DLToastItem) -> Void = { _ in }
    /// The universe's first citizen (lowest id): their colour is terracotta, the other's sage.
    @Entry var dlFirstCitizen: Int? = nil
    /// The universe's name, wherever the web says "Delulutopia" (Universe C48).
    @Entry var dlBrand: String = "Delulutopia"
}

public extension View {
    /// Shows a plain toast.
    func dlNotify(_ notice: @escaping @MainActor (DLToastItem) -> Void) -> some View {
        environment(\.dlNotice, notice)
    }
}

@MainActor
public extension DLToastItem {
    static func text(_ text: String) -> DLToastItem { DLToastItem(text) }
}
