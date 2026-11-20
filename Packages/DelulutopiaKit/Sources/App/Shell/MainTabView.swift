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

/// The floating glass tab bar on iOS 26+ (the system draws it), the classic bar before. Each tab
/// keeps its own navigation stack; `dlOpen` pushes on the current one, `dlNotice` shows a toast
/// above the bar.
struct MainTabView: View {
    @Binding var selection: AppTab
    @Environment(Backend.self) var backend
    @Environment(\.colorScheme) var colorScheme
    @State private var paths: [AppTab: [AppRoute]] = [:]
    @State private var toast: DLToastItem?
    /// Your picture for the You tab (iOS design §3: 26 pt, accent ring when selected).
    @State private var youPhoto: UIImage?

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: path(tab)) {
                    root(for: tab)
                        // Tabs slide in from the side they sit on (Android PR #8 parity, 20 Nov).
                        .modifier(TabSlide(index: AppTab.allCases.firstIndex(of: tab) ?? 0,
                                           selected: AppTab.allCases.firstIndex(of: selection) ?? 0))
                        .overlay { if tab != .you { LeafLayer() } }
                        .navigationDestination(for: AppRoute.self) { route in
                            RouteScreen(route: route)
                        }
                }
                .tabItem { tabLabel(tab) }
                .tag(tab)
            }
        }
        .environment(\.dlOpen) { route in
            // Universe U8: alone, starting a letter, discussion or email only explains why not.
            if alone, route.startsNew {
                toast = DLToastItem(t("common.noFriendNotice", ["name": backend.home.home?.universe.name ?? "Delulutopia"]))
                return
            }
            paths[selection, default: []].append(route)
        }
        .environment(\.dlAlone, alone)
        .environment(\.dlReplace) { route in
            var stack = paths[selection, default: []]
            if !stack.isEmpty { stack.removeLast() }
            stack.append(route)
            paths[selection] = stack
        }
        .environment(\.dlSelectTab) { tab in
            paths[tab] = []
            selection = tab
        }
        .environment(\.dlNotice) { item in toast = item }
        .environment(\.dlBrand, backend.home.home?.universe.name ?? "Delulutopia")
        .environment(\.dlFirstCitizen, backend.home.home?.firstCitizen)
        .dlToast($toast, bottom: 96)
        .task(id: backend.home.home?.me.avatarUrl) {
            guard let url = backend.home.home?.me.avatarUrl else {
                youPhoto = nil
                return
            }
            youPhoto = await ImageCache.shared.load(url, client: backend.client, maxPixel: 96)
        }
        .onChange(of: arrivals) { old, new in announce(old: old, new: new) }
        // A tapped notification (iOS design I-5); logged out, it waited here for the PIN.
        .onChange(of: backend.push.pendingLink, initial: true) { _, link in
            if let link { open(link) }
        }
        // The icon badge follows the tab dots as items are read (Q7).
        .onChange(of: unreadTotal) { _, total in
            if let total { backend.push.setBadge(total) }
        }
    }

    /// This iPhone shows no notifications: the red dot on You (iOS design §3).
    private var notificationsOff: Bool {
        backend.push.permission == .blocked || backend.push.permission == .notAsked
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
        let target: (AppTab, [AppRoute]) =
            switch link {
            case .home: (.home, [])
            case .letters: (.letters, [])
            case let .letter(id): (.letters, [.letter(id)])
            case .discussions: (.discussions, [])
            case let .discussion(id): (.discussions, [.discussion(id)])
            case .emails: (.emails, [])
            case let .thread(id): (.emails, [.thread(id)])
            case .notificationSettings: (.you, [.notifications])
            }
        paths[target.0] = target.1
        selection = target.0
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
                selection = .letters
                paths[.letters] = [.letter(id)]
            }
        case "d":
            toast = DLToastItem(t("notify.inTab.discussion", ["name": friend]), symbol: "note.text", actionTitle: t("common.open")) {
                selection = .discussions
                paths[.discussions] = [.discussion(id)]
            }
        default:
            let thread = h.newEmails.first { $0.id == id }?.threadId ?? id
            toast = DLToastItem(t("notify.inTab.email", ["name": friend]), symbol: "at", actionTitle: t("common.open")) {
                selection = .emails
                paths[.emails] = [.thread(thread)]
            }
        }
    }

    /// Tapping the current tab again pops it to its root (iOS convention).
    private var tabSelection: Binding<AppTab> {
        Binding(get: { selection }, set: { tab in
            if tab == selection { paths[tab] = [] }
            selection = tab
        })
    }

    private func path(_ tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
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
                    selected: selection == .you,
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
                Image(uiImage: DotTabIcon.image(symbol: tab.symbol, selected: selection == tab, style: style))
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
