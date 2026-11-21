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

/// How the shell lays itself out (doc "Delululand — iPad Layout" §2): the iPhone stacks, the iPhone
/// Duo's unfolded display (iPhone navigation with wide layouts, IP10), or the iPad split (IP2).
public enum AppLayout: String, Sendable, Equatable {
    case phone
    case widePhone
    case split

    /// Regular width on an iPad is the split; regular width on an iPhone only happens on the Duo's
    /// inner display (standard iPhones are portrait-locked). Everything else is the iPhone layout.
    public static func resolve(pad: Bool, regularWidth: Bool) -> AppLayout {
        guard regularWidth else { return .phone }
        return pad ? .split : .widePhone
    }

    /// The widest a reading column grows (canvas: thread and composers 660 pt on iPad, 680 pt on the
    /// Duo); nil on the iPhone, which keeps the full width.
    public var readableWidth: CGFloat? {
        switch self {
        case .phone: nil
        case .widePhone: 680
        case .split: 660
        }
    }
}

public extension AppRoute {
    /// The tab a route belongs to, for routes opened from Home on the iPad (IP3) and from links.
    var tab: AppTab {
        switch self {
        case .letter, .write: .letters
        case .discussion, .composeDiscussion, .archived: .discussions
        case .thread, .newEmail: .emails
        case .friend, .profile, .universe, .appearance, .notifications, .language: .you
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
    /// How the shell is laid out (iPad Layout §2); features widen their layouts from it.
    @Entry var dlLayout: AppLayout = .phone
    /// Set on a screen that is the root of the iPad's detail column or a full-screen cover, where
    /// `dismiss` has nothing to pop: it clears the selection or closes the cover. Nil elsewhere.
    @Entry var dlClose: (@MainActor () -> Void)? = nil
    /// The route shown in the iPad's detail column for this tab, so the list can mark its row.
    @Entry var dlSelected: AppRoute? = nil
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

public extension View {
    /// Caps a reading column at the layout's width and centres it (iPad Layout IP2, IP10).
    func dlReadable(_ layout: AppLayout) -> some View {
        modifier(DLReadable(width: layout.readableWidth))
    }

    /// Outlines a list row while its item is open in the iPad's detail column (canvas T-Emails).
    func dlSelectedRow(_ route: AppRoute) -> some View {
        modifier(DLSelectedRow(route: route))
    }
}

private struct DLReadable: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(maxWidth: width).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

private struct DLSelectedRow: ViewModifier {
    let route: AppRoute
    @Environment(\.dlSelected) private var selected

    func body(content: Content) -> some View {
        content
            .overlay {
                if selected == route {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.dlSeal, lineWidth: 2.5).padding(-2)
                }
            }
            .accessibilityAddTraits(selected == route ? .isSelected : [])
            .hoverEffect(.highlight)
    }
}

/// Leaves a screen: closes the iPad detail column or cover when the shell set `dlClose`, else pops.
@MainActor
public func dlLeave(_ close: (@MainActor () -> Void)?, _ dismiss: DismissAction) {
    if let close { close() } else { dismiss() }
}

extension AppRoute: Identifiable {
    public var id: AppRoute { self }
}

public extension AppRoute {
    /// The ⌘N command's title for the list it starts something on (iPad Layout IP8).
    var newItemTitle: String {
        switch self {
        case .write: t("letters.writeALetter")
        case .composeDiscussion: t("discussions.newDiscussion")
        case .newEmail: t("emails.newEmail")
        default: ""
        }
    }
}

public extension View {
    /// Reading and writing pages hide the iPhone's tab bar; on the iPad the tab bar stays over both
    /// columns (iPad Layout IP1), so a page in the detail column leaves it alone.
    func dlHidesTabBar() -> some View {
        modifier(DLHidesTabBar())
    }
}

private struct DLHidesTabBar: ViewModifier {
    @Environment(\.dlLayout) private var layout

    func body(content: Content) -> some View {
        if layout == .split {
            content
        } else {
            content.toolbar(.hidden, for: .tabBar)
        }
    }
}
