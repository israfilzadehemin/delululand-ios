import DLData
import DLUI

/// Where each tab stands (doc "Delululand — iPad Layout" §5, §6). On the iPhone (and the Duo) a tab
/// is one stack, `paths[tab]`, exactly as before. On the iPad split a tab with a list has a selection
/// shown in its detail column, and `paths[tab]` is what was pushed on top of it there; Discussions can
/// also show its Archived list in the list column; Write opens as a full-screen cover.
///
/// A value type so the rules are plain functions the unit tests drive (AppShellTests).
struct TabNavigation: Equatable {
    private(set) var layout: AppLayout
    var selected: AppTab
    var paths: [AppTab: [AppRoute]] = [:]
    var selections: [AppTab: AppRoute] = [:]
    /// Discussions' list column shows Archived (split only).
    var archivedList = false
    /// The letter being written, shown as a full-screen cover (split only, IP6).
    var cover: AppRoute?

    init(layout: AppLayout = .phone, selected: AppTab = .home) {
        self.layout = layout
        self.selected = selected
    }

    /// Tabs whose split shows a list beside a detail column (IP2). Home stays two columns (IP3).
    static func hasDetail(_ tab: AppTab) -> Bool {
        tab != .home
    }

    /// Whether a route is what a tab's detail column shows as its root (as opposed to a page pushed
    /// on top of it there).
    static func selectable(_ route: AppRoute, in tab: AppTab) -> Bool {
        switch (tab, route) {
        // A new discussion fills the detail column; editing one is pushed over it, so Save comes back.
        case (.discussions, .composeDiscussion(editId: nil)):
            true
        case (.letters, .letter),
             (.discussions, .discussion),
             (.emails, .thread), (.emails, .newEmail),
             (.you, .profile), (.you, .friend), (.you, .universe), (.you, .appearance),
             (.you, .notifications), (.you, .language):
            true
        default:
            false
        }
    }

    /// The You tab opens on Profile in the split (IP4).
    static let youDefault: AppRoute = .profile

    func path(_ tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }

    /// The detail column's root for a tab (split): its selection, else You's default.
    func selection(_ tab: AppTab) -> AppRoute? {
        selections[tab] ?? (tab == .you ? Self.youDefault : nil)
    }

    // MARK: Opening

    /// `dlOpen` from a screen on the selected tab.
    mutating func open(_ route: AppRoute) {
        guard layout == .split else {
            paths[selected, default: []].append(route)
            return
        }
        if case .write = route {
            cover = route
            return
        }
        // From Home (no detail column) a route opens on the tab it belongs to (IP3).
        let tab = Self.hasDetail(selected) ? selected : route.tab
        if route == .archived, tab == .discussions {
            archivedList = true
            selected = tab
            return
        }
        if Self.selectable(route, in: tab) {
            selections[tab] = route
            paths[tab] = []
        } else if Self.hasDetail(tab) {
            paths[tab, default: []].append(route)
        }
        selected = tab
    }

    /// `dlReplace`: swaps the top of the current stack (New email → its thread after Send).
    mutating func replace(_ route: AppRoute) {
        guard layout == .split else {
            var stack = paths[selected, default: []]
            if !stack.isEmpty { stack.removeLast() }
            stack.append(route)
            paths[selected] = stack
            return
        }
        if case .write = route {
            cover = route
            return
        }
        if cover != nil { cover = nil }
        let tab = Self.hasDetail(selected) ? selected : route.tab
        var stack = paths[tab, default: []]
        if !stack.isEmpty {
            stack.removeLast()
            stack.append(route)
            paths[tab] = stack
        } else if Self.selectable(route, in: tab) {
            selections[tab] = route
        } else {
            paths[tab] = [route]
        }
        selected = tab
    }

    /// `dlSelectTab`: switches tab and returns it to its root (the list, nothing selected).
    mutating func selectTab(_ tab: AppTab) {
        paths[tab] = []
        if layout == .split {
            selections[tab] = nil
            if tab == .discussions { archivedList = false }
            cover = nil
        }
        selected = tab
    }

    /// Tapping the current tab again pops it to its root (iOS convention); other taps just switch.
    mutating func tapTab(_ tab: AppTab) {
        if tab == selected {
            paths[tab] = []
            if layout == .split, tab == .discussions { archivedList = false }
        }
        selected = tab
    }

    /// The detail column's root closes (`dlClose`): nothing is selected any more.
    mutating func closeDetail(_ tab: AppTab) {
        selections[tab] = nil
        paths[tab] = []
    }

    /// A notification, widget or in-app notice names a screen (iOS design I-5): its tab, over the
    /// tab's root.
    mutating func open(link: AppLink) {
        let target: (AppTab, AppRoute?) =
            switch link {
            case .home: (.home, nil)
            case .letters: (.letters, nil)
            case let .letter(id): (.letters, .letter(id))
            case .discussions: (.discussions, nil)
            case let .discussion(id): (.discussions, .discussion(id))
            case .emails: (.emails, nil)
            case let .thread(id): (.emails, .thread(id))
            case .notificationSettings: (.you, .notifications)
            }
        show(target.0, target.1)
    }

    /// Opens `route` (or the bare tab) on `tab`, replacing what that tab showed.
    mutating func show(_ tab: AppTab, _ route: AppRoute?) {
        cover = nil
        if layout == .split {
            if tab == .discussions { archivedList = false }
            if let route, Self.selectable(route, in: tab) {
                selections[tab] = route
            } else {
                selections[tab] = nil
            }
            paths[tab] = []
        } else {
            paths[tab] = route.map { [$0] } ?? []
        }
        selected = tab
    }

    // MARK: Changing layout (rotation of a resized window, Stage Manager, Slide Over)

    /// Moves every tab's state across, so a window that crosses the compact/regular line keeps what
    /// was open (§6).
    mutating func relayout(_ new: AppLayout) {
        let wasSplit = layout == .split
        let isSplit = new == .split
        layout = new
        guard wasSplit != isSplit else { return }
        if isSplit {
            expand()
        } else {
            collapse()
        }
    }

    /// Split → stacks: each tab's selection goes under what was pushed on it.
    private mutating func collapse() {
        for tab in AppTab.allCases {
            var stack: [AppRoute] = []
            if tab == .discussions, archivedList { stack.append(.archived) }
            if let s = selections[tab] { stack.append(s) }
            stack += paths[tab] ?? []
            paths[tab] = stack
        }
        if let cover {
            paths[.letters, default: []].append(cover)
            if selected != .letters { selected = .letters }
        }
        selections = [:]
        archivedList = false
        cover = nil
    }

    /// Stacks → split: the first selectable route becomes the selection, the rest stays pushed on it.
    private mutating func expand() {
        for tab in AppTab.allCases {
            var stack = paths[tab] ?? []
            if tab == .discussions, stack.first == .archived {
                archivedList = true
                stack.removeFirst()
            }
            if let last = stack.last, case .write = last {
                cover = last
                stack.removeLast()
            }
            guard Self.hasDetail(tab) else {
                // Home keeps no stack in the split: what was open moves to its own tab.
                if let first = stack.first, Self.selectable(first, in: first.tab) {
                    selections[first.tab] = first
                    paths[first.tab] = Array(stack.dropFirst())
                }
                paths[tab] = []
                continue
            }
            if let first = stack.first, Self.selectable(first, in: tab) {
                selections[tab] = first
                paths[tab] = Array(stack.dropFirst())
            } else {
                paths[tab] = stack
            }
        }
    }
}
