import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import SwiftUI

/// Places a screen can open, whichever tab it lives in (the Android `AppNav` routes). The shell
/// pushes them on the current tab's stack and maps each to its screen.
public enum AppRoute: Hashable, Sendable {
    case letter(PublicID)
    case write(editId: PublicID? = nil, replyTo: PublicID? = nil)
    case discussion(PublicID)
    case composeDiscussion(editId: PublicID?)
    case archived
    case thread(PublicID)
    case newEmail
    case friend
    case profile
    case universe
    case appearance
    case notifications
    case language
}

/// The tabs, for opening one from anywhere (a toast, an arrival notice, a notification).
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home, letters, discussions, emails, you

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: t("tabs.home")
        case .letters: t("tabs.letters")
        case .discussions: t("tabs.discussions")
        case .emails: t("tabs.emails")
        case .you: t("tabs.you")
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
    /// Replaces the top route of the current tab's stack in one step (pop + push together, so the
    /// stack never animates through a half-built state — e.g. New email → its thread after Send).
    @Entry var dlReplace: @MainActor (AppRoute) -> Void = { _ in }
    /// Switches tab (and pops it to its root when `root` is set).
    @Entry var dlSelectTab: @MainActor (AppTab) -> Void = { _ in }
    /// Shows a toast above the tab bar.
    @Entry var dlNotice: @MainActor (DLToastItem) -> Void = { _ in }
    /// The universe's first citizen (lowest id): their colour is terracotta, the other's sage.
    @Entry var dlFirstCitizen: PublicID? = nil
    /// The universe's name, wherever the web says "Delulutopia" (Universe C48).
    @Entry var dlBrand: String = "Delulutopia"
    /// The creator is alone in the universe (Universe U8): new letters, discussions and emails are off.
    @Entry var dlAlone: Bool = false
}

public extension AppRoute {
    /// A route that starts something new for the friend (blocked while nobody has joined, U8).
    var startsNew: Bool {
        switch self {
        case let .write(editId, replyTo): editId == nil && replyTo == nil
        case let .composeDiscussion(editId): editId == nil
        case .newEmail: true
        default: false
        }
    }
}

public extension View {
    /// Greys a new-item button while the creator is alone (A-Create-alone). The tap still reaches
    /// `dlOpen`, which answers with the "Nobody to write to yet" toast instead of opening.
    func dlNewItemButton() -> some View { modifier(DLNewItemDim()) }
}

private struct DLNewItemDim: ViewModifier {
    @Environment(\.dlAlone) private var alone

    func body(content: Content) -> some View {
        content
            .opacity(alone ? 0.4 : 1)
            .accessibilityHint(alone ? t("common.noFriend") : "")
    }
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
