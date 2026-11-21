import DLData
import DLI18n
import FeatureHome
import FeatureDiscussions
import FeatureEmails
import FeatureLetters
import DLDesignSystem
import DLUI
import SwiftUI
import UIKit
import WidgetKit

/// The floating glass tab bar on iOS 26+ (the system draws it), the classic bar before. Each tab
/// keeps its own navigation stack; `dlOpen` pushes on the current one, `dlNotice` shows a toast
/// above the bar. On the iPad (regular width) Letters, Discussions, Emails and You become a list
/// beside a detail column and the tab bar can turn into a sidebar (doc "Delululand — iPad Layout").
struct MainTabView: View {
    @Binding var selection: AppTab
    /// Screenshots pin a layout; the app reads it from the device and the window's width.
    let forcedLayout: AppLayout?
    @Environment(Backend.self) var backend
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var nav: TabNavigation
    @State private var toast: DLToastItem?
    /// Your picture for the You tab (iOS design §3: 26 pt, accent ring when selected).
    @State private var youPhoto: UIImage?

    init(selection: Binding<AppTab>, forcedLayout: AppLayout? = nil) {
        _selection = selection
        self.forcedLayout = forcedLayout
        _nav = State(initialValue: TabNavigation(layout: forcedLayout ?? .phone, selected: selection.wrappedValue))
    }

    private var layout: AppLayout {
        forcedLayout ?? .resolve(pad: UIDevice.current.userInterfaceIdiom == .pad, regularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        tabs
            .fullScreenCover(item: coverBinding) { route in
                NavigationStack {
                    RouteScreen(route: route)
                }
                .environment(\.dlClose) { nav.cover = nil }
            }
            .environment(\.dlLayout, nav.layout)
            .environment(\.dlOpen) { route in
                // Universe U8: alone, starting a letter, discussion or email only explains why not.
                if alone, route.startsNew {
                    toast = DLToastItem(t("common.noFriendNotice", ["name": backend.home.home?.universe.name ?? "Delulutopia"]))
                    return
                }
                nav.open(route)
            }
            .environment(\.dlAlone, alone)
            .environment(\.dlReplace) { route in nav.replace(route) }
            .environment(\.dlSelectTab) { tab in nav.selectTab(tab) }
            .environment(\.dlNotice) { item in toast = item }
            .environment(\.dlBrand, backend.home.home?.universe.name ?? "Delulutopia")
            .environment(\.dlFirstCitizen, backend.home.home?.firstCitizen)
            .dlToast($toast, bottom: nav.layout == .split ? 24 : 96)
            // Keyboard shortcuts for the iPad and the Duo (IP8); the iPhone's tree stays as it was.
            .background { if nav.layout != .phone { shortcuts } }
            .task(id: backend.home.home?.me.avatarUrl) {
                guard let url = backend.home.home?.me.avatarUrl else {
                    youPhoto = nil
                    return
                }
                youPhoto = await ImageCache.shared.load(url, client: backend.client, maxPixel: 96)
            }
            .onChange(of: layout, initial: true) { _, new in
                if nav.layout != new { nav.relayout(new) }
            }
            .onChange(of: nav.selected) { _, tab in
                if selection != tab { selection = tab }
            }
            .onChange(of: arrivals) { old, new in announce(old: old, new: new) }
            // A tapped notification (iOS design I-5); logged out, it waited here for the PIN.
            .onChange(of: backend.push.pendingLink, initial: true) { _, link in
                if let link { open(link) }
            }
            // Widgets show the board, the selfies, the clocks and moods (WG3): what they show changed.
            .onChange(of: widgetSignature) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
            // The icon badge follows the tab dots as items are read (Q7).
            .onChange(of: unreadTotal) { _, total in
                if let total { backend.push.setBadge(total) }
            }
    }

    // MARK: Tabs

    @ViewBuilder
    private var tabs: some View {
        if nav.layout == .split {
            if #available(iOS 18.0, *) {
                // iPad Layout IP1: the tab bar sits on top and can turn into a sidebar.
                TabView(selection: tabSelection) {
                    ForEach(AppTab.allCases) { tab in
                        Tab(value: tab) {
                            splitTab(tab)
                        } label: {
                            tabLabel(tab)
                        }
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                // The canvas's tab bar on top, with the "Show sidebar" button to switch.
                .defaultAdaptableTabBarPlacement(.tabBar)
            } else {
                TabView(selection: tabSelection) {
                    ForEach(AppTab.allCases) { tab in
                        splitTab(tab)
                            .tabItem { tabLabel(tab) }
                            .tag(tab)
                    }
                }
            }
        } else {
            // The iPhone and the Duo: each tab's stack is the TabView's direct child, as before.
            TabView(selection: tabSelection) {
                ForEach(AppTab.allCases) { tab in
                    stackTab(tab)
                        .tabItem { tabLabel(tab) }
                        .tag(tab)
                }
            }
        }
    }

    /// The iPhone (and Duo) tab: one stack.
    private func stackTab(_ tab: AppTab) -> some View {
        NavigationStack(path: path(tab)) {
            root(for: tab)
                // Tabs slide in from the side they sit on (Android PR #8 parity, 20 Nov).
                .modifier(TabSlide(index: AppTab.allCases.firstIndex(of: tab) ?? 0,
                                   selected: AppTab.allCases.firstIndex(of: nav.selected) ?? 0))
                .overlay { if tab != .you { LeafLayer() } }
                .navigationDestination(for: AppRoute.self) { route in
                    RouteScreen(route: route)
                        .dlReadable(nav.layout)
                }
        }
    }

    /// The iPad tab (IP2, IP3): Home in two columns; the others a list beside a detail column. The
    /// columns are two stacks side by side rather than a NavigationSplitView, which hides the
    /// floating tab bar; the widths are the canvas's (T-Letters 390 pt, T-Emails and T-You 420 pt,
    /// 340 pt in portrait).
    @ViewBuilder
    private func splitTab(_ tab: AppTab) -> some View {
        if TabNavigation.hasDetail(tab) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    NavigationStack(path: listPath(tab)) {
                        root(for: tab)
                            .navigationDestination(for: AppRoute.self) { route in
                                RouteScreen(route: route)
                            }
                    }
                    .environment(\.dlSelected, nav.selection(tab))
                    .frame(width: Self.listWidth(tab, size: geo.size))
                    Rectangle()
                        .fill(Color.dlLine)
                        .frame(width: 0.5)
                        .ignoresSafeArea(edges: .bottom)
                    NavigationStack(path: path(tab)) {
                        detailRoot(tab)
                            .navigationDestination(for: AppRoute.self) { route in
                                RouteScreen(route: route)
                                    .dlReadable(nav.layout)
                            }
                    }
                    .overlay { if tab != .you { LeafLayer() } }
                }
            }
        } else {
            NavigationStack {
                root(for: tab)
                    .overlay { LeafLayer() }
            }
        }
    }

    static func listWidth(_ tab: AppTab, size: CGSize) -> CGFloat {
        guard size.width > size.height else { return 340 }
        return tab == .emails || tab == .you ? 420 : 390
    }

    @ViewBuilder
    private func detailRoot(_ tab: AppTab) -> some View {
        if let route = nav.selection(tab) {
            RouteScreen(route: route)
                .id(route)
                .dlReadable(nav.layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.dlPaper.ignoresSafeArea())
                .environment(\.dlClose) { nav.closeDetail(tab) }
        } else {
            SplitHint(tab: tab)
        }
    }

    // MARK: Keyboard (IP8)

    /// ⌘1–⌘5 switch tabs; ⌘N starts a new item on Letters, Discussions and Emails. Hidden buttons
    /// carry the shortcuts so the system lists them when ⌘ is held.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { i, tab in
                Button(tab.title) { nav.tapTab(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            if let route = newItemRoute {
                Button(route.newItemTitle) {
                    if alone {
                        toast = DLToastItem(t("common.noFriendNotice", ["name": backend.home.home?.universe.name ?? "Delulutopia"]))
                    } else {
                        nav.open(route)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var newItemRoute: AppRoute? {
        switch nav.selected {
        case .letters: .write(editId: nil)
        case .discussions: .composeDiscussion(editId: nil)
        case .emails: .newEmail
        default: nil
        }
    }

    /// This iPhone shows no notifications: the red dot on You (iOS design §3).
    private var notificationsOff: Bool {
        backend.push.permission == .blocked || backend.push.permission == .notAsked
    }

    /// Everything the widgets show; a change reloads their timelines (WG3).
    private var widgetSignature: String {
        guard let h = backend.home.home else { return "" }
        let selfies = [h.selfies?.mine, h.selfies?.theirs].map { s in s.map { "\($0.id):\($0.locked)" } ?? "-" }
        return [
            "\(h.board?.version ?? 0)", h.board?.authorId ?? "", "\(h.boardNew)",
            selfies.joined(separator: ","),
            h.me.nickname, h.me.mood ?? "", h.me.timezone ?? "", h.me.language ?? "",
            h.friend?.nickname ?? "", h.friend?.mood ?? "", h.friend?.timezone ?? "", h.universe.name,
        ].joined(separator: "|")
    }

    /// Nobody has joined yet (Home loaded, no friend).
    private var alone: Bool {
        guard let h = backend.home.home else { return false }
        return h.friend == nil
    }

    /// Letters, discussions and emails waiting, as the server counts the badge; nil before Home loads.
    private var unreadTotal: Int? {
        guard let h = backend.home.home else { return nil }
        return h.unreadCount + h.discussionsUnseen + h.emailsUnread + h.emailsReacted
    }

    /// Opens a notification's screen on its own tab, over that tab's root.
    private func open(_ link: AppLink) {
        backend.push.pendingLink = nil
        nav.open(link: link)
        // A widget tap that lands on Home names what to open there (WG4).
        if let intent = link.homeIntent { backend.push.homeIntent = intent }
        backend.home.refreshSoon()
    }

    /// What has arrived for me now: delivered letters, new discussions, new emails.
    private var arrivals: [String] {
        guard let h = backend.home.home else { return [] }
        let now = DLTime.now
        let letters = h.from.filter { LetterState.of($0, now: now) == LetterState.delivered }.map { "l\($0.id)" }
        return letters + h.newDiscussions.map { "d\($0.id)" } + h.newEmails.map { "e\($0.id)" }
    }

    /// In-app arrival notices (web inTab fallback): one toast for the newest thing that arrived
    /// while the app is open, with Open.
    private func announce(old: [String], new: [String]) {
        guard !old.isEmpty || backend.home.home != nil, let h = backend.home.home else { return }
        let fresh = new.filter { !old.contains($0) }
        guard !old.isEmpty, let key = fresh.first else { return }
        let friend = h.friend?.nickname ?? t("common.friend")
        let id = String(key.dropFirst())
        switch key.first {
        case "l":
            toast = DLToastItem(t("notify.inTab.letter", ["name": friend]), symbol: "envelope", actionTitle: t("common.open")) {
                nav.show(.letters, .letter(id))
            }
        case "d":
            toast = DLToastItem(t("notify.inTab.discussion", ["name": friend]), symbol: "note.text", actionTitle: t("common.open")) {
                nav.show(.discussions, .discussion(id))
            }
        default:
            let thread = h.newEmails.first { $0.id == id }?.threadId ?? id
            toast = DLToastItem(t("notify.inTab.email", ["name": friend]), symbol: "at", actionTitle: t("common.open")) {
                nav.show(.emails, .thread(thread))
            }
        }
    }

    /// Tapping the current tab again pops it to its root (iOS convention).
    private var tabSelection: Binding<AppTab> {
        Binding(get: { nav.selected }, set: { nav.tapTab($0) })
    }

    private func path(_ tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { nav.path(tab) }, set: { nav.paths[tab] = $0 })
    }

    /// The list column's own stack: Discussions' Archived list (split only).
    private func listPath(_ tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { tab == .discussions && nav.archivedList ? [.archived] : [] },
            set: { if tab == .discussions { nav.archivedList = !$0.isEmpty } }
        )
    }

    private var coverBinding: Binding<AppRoute?> {
        Binding(get: { nav.cover }, set: { nav.cover = $0 })
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeScreen()
        case .letters:
            LettersScreen()
        case .discussions:
            DiscussionsScreen()
        case .emails:
            EmailsScreen()
        case .you:
            YouScreen(config: backend.config, settings: backend.settings)
        default:
            PlaceholderScreen(tab: tab)
        }
    }

    private func hasNew(_ tab: AppTab) -> Bool {
        guard let h = backend.home.home else { return false }
        switch tab {
        case .letters: return h.unreadCount > 0
        case .discussions: return h.discussionsUnseen > 0
        case .emails: return h.emailsUnread + h.emailsReacted > 0
        default: return false
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: AppTab) -> some View {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if tab == .you {
            Label {
                Text(tab.title)
            } icon: {
                Image(uiImage: YouTabIcon.image(
                    selected: nav.selected == .you,
                    style: style,
                    photo: youPhoto,
                    initial: backend.home.home.map { String($0.me.nickname.prefix(1)).uppercased() },
                    dot: notificationsOff
                ))
            }
            .accessibilityLabel(notificationsOff ? t("tabs.titleNew", ["title": tab.title]) : tab.title)
        } else if hasNew(tab) {
            Label {
                Text(tab.title)
            } icon: {
                Image(uiImage: DotTabIcon.image(symbol: tab.symbol, selected: nav.selected == tab, style: style))
            }
            .accessibilityLabel(t("tabs.titleNew", ["title": tab.title]))
        } else {
            Label(tab.title, systemImage: tab.symbol)
                // Canvas tab bar: outline icons; iOS fills tab symbols by default (user report 20 Nov).
                .environment(\.symbolVariants, .none)
        }
    }
}

/// A tab symbol with the navy "new" dot at its top-right (canvas tab bar: 9 pt, white halo).
@MainActor
enum DotTabIcon {
    static func image(symbol: String, selected: Bool, style: UIUserInterfaceStyle) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: selected ? .semibold : .regular)
        let traits = UITraitCollection(userInterfaceStyle: style)
        let ink = (selected ? DLPalette.seal : DLPalette.ink).value(for: style).uiColor
        guard let base = UIImage(systemName: symbol, withConfiguration: config)?.withTintColor(ink, renderingMode: .alwaysOriginal) else {
            return UIImage()
        }
        let size = CGSize(width: base.size.width + 8, height: base.size.height + 4)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(at: CGPoint(x: 2, y: 4))
            let dot = CGRect(x: size.width - 10, y: 0, width: 9, height: 9)
            UIColor.white.withAlphaComponent(0.78).setFill()
            UIBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2)).fill()
            DLPalette.seal.value(for: style).uiColor.resolvedColor(with: traits).setFill()
            UIBezierPath(ovalIn: dot).fill()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

/// A pushed screen for a route. Screens that have not landed yet show the placeholder line.
struct RouteScreen: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case let .letter(id):
            LetterScreen(id: id)
        case let .write(editId, replyTo):
            WriteScreen(editId: editId, replyTo: replyTo)
        case let .discussion(id):
            DiscussionScreen(id: id)
        case let .composeDiscussion(editId):
            ComposeDiscussionScreen(editId: editId)
        case .archived:
            DiscussionsScreen(archived: true)
        case let .thread(id):
            ThreadScreen(id: id)
        case .newEmail:
            NewEmailScreen()
        case .appearance:
            AppearanceScreenHost()
        case .profile:
            ProfileScreen()
        case .friend:
            FriendScreen()
        case .universe:
            UniverseScreen()
        case .notifications:
            NotificationsScreen()
        case .language:
            LanguageScreen()
        }
    }
}

private struct AppearanceScreenHost: View {
    @Environment(Backend.self) var backend
    var body: some View { AppearanceScreen(settings: backend.settings) }
}

/// The You tab shows the citizen's picture at 26 pt with an accent ring when selected (iOS design §3);
/// initials on the paper tint until it loads, and the red dot while this iPhone's notifications are off.
@MainActor
enum YouTabIcon {
    static func image(selected: Bool, style: UIUserInterfaceStyle, photo: UIImage?, initial: String?, dot: Bool) -> UIImage {
        let size = CGSize(width: 32, height: 30)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(x: 2, y: 2, width: 26, height: 26)
            let circle = UIBezierPath(ovalIn: rect)
            DLPalette.userATint.value(for: style).uiColor.setFill()
            circle.fill()

            if let photo {
                UIGraphicsGetCurrentContext()?.saveGState()
                circle.addClip()
                photo.draw(in: rect)
                UIGraphicsGetCurrentContext()?.restoreGState()
            } else if let initial, !initial.isEmpty {
                let font = UIFont.systemFont(ofSize: 12, weight: .heavy)
                let ink = DLPalette.ink.value(for: style).uiColor
                let text = NSAttributedString(string: initial, attributes: [.font: font, .foregroundColor: ink])
                let box = text.size()
                text.draw(at: CGPoint(x: rect.midX - box.width / 2, y: rect.midY - box.height / 2))
            } else {
                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                if let person = UIImage(systemName: "person.fill", withConfiguration: symbolConfig)?
                    .withTintColor(DLPalette.inkQuiet.value(for: style).uiColor, renderingMode: .alwaysOriginal) {
                    person.draw(at: CGPoint(x: rect.midX - person.size.width / 2, y: rect.midY - person.size.height / 2 + 1))
                }
            }

            let ring = UIBezierPath(ovalIn: selected ? rect.insetBy(dx: -1, dy: -1) : rect)
            ring.lineWidth = selected ? 2 : 0.5
            (selected ? DLPalette.seal : DLPalette.line).value(for: style).uiColor.setStroke()
            ring.stroke()

            if dot {
                let badge = CGRect(x: size.width - 11, y: 0, width: 10, height: 10)
                UIColor.white.withAlphaComponent(0.78).setFill()
                UIBezierPath(ovalIn: badge.insetBy(dx: -2, dy: -2)).fill()
                UIColor.systemRed.setFill()
                UIBezierPath(ovalIn: badge).fill()
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}


/// A tab's root slides in by position when it becomes the selected tab: from the right when it sits
/// to the right of the tab that was showing, from the left otherwise (Design Consistency, Nov 2026).
private struct TabSlide: ViewModifier {
    let index: Int
    let selected: Int
    @State private var shift: CGFloat = 0
    @State private var fade: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dlMotionEnabled) private var motionEnabled

    func body(content: Content) -> some View {
        content
            .offset(x: shift)
            .opacity(fade)
            .onChange(of: selected) { old, new in
                guard new == index, old != new, motionEnabled, !reduceMotion else { return }
                var jump = Transaction()
                jump.disablesAnimations = true
                withTransaction(jump) {
                    shift = new > old ? 56 : -56
                    fade = 0.35
                }
                withAnimation(.spring(duration: 0.34, bounce: 0)) {
                    shift = 0
                    fade = 1
                }
            }
    }
}
