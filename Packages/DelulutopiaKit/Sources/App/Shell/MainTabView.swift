import DLData
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

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: path(tab)) {
                    root(for: tab)
                        .overlay { if tab != .you { LeafLayer() } }
                        .navigationDestination(for: AppRoute.self) { route in
                            RouteScreen(route: route)
                        }
                }
                .tabItem { tabLabel(tab) }
                .tag(tab)
            }
        }
        .environment(\.dlOpen) { route in paths[selection, default: []].append(route) }
        .environment(\.dlSelectTab) { tab in
            paths[tab] = []
            selection = tab
        }
        .environment(\.dlNotice) { item in toast = item }
        .environment(\.dlBrand, backend.home.home?.universe.name ?? "Delulutopia")
        .environment(\.dlFirstCitizen, backend.home.home?.firstCitizen)
        .dlToast($toast, bottom: 96)
        .onChange(of: arrivals) { old, new in announce(old: old, new: new) }
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
        let friend = h.friend?.nickname ?? "Your friend"
        let id = Int(key.dropFirst()) ?? 0
        switch key.first {
        case "l":
            toast = DLToastItem("\(friend)’s letter arrived", symbol: "envelope", actionTitle: "Open") {
                selection = .letters
                paths[.letters] = [.letter(id)]
            }
        case "d":
            toast = DLToastItem("\(friend) started a discussion", symbol: "note.text", actionTitle: "Open") {
                selection = .discussions
                paths[.discussions] = [.discussion(id)]
            }
        default:
            let thread = h.newEmails.first { $0.id == id }?.threadId ?? id
            toast = DLToastItem("\(friend) sent you an email", symbol: "at", actionTitle: "Open") {
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
                Image(uiImage: YouTabIcon.image(selected: selection == .you, style: style))
            }
        } else if hasNew(tab) {
            Label {
                Text(tab.title)
            } icon: {
                Image(uiImage: DotTabIcon.image(symbol: tab.symbol, selected: selection == tab, style: style))
            }
            .accessibilityLabel("\(tab.title), new")
        } else {
            Label(tab.title, systemImage: tab.symbol)
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
        default:
            ScrollView {
                Text("This screen arrives in the next build.")
                    .dlText(.callout)
                    .foregroundStyle(.dlInkQuiet)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
            .background(.dlPaper)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AppearanceScreenHost: View {
    @Environment(Backend.self) var backend
    var body: some View { AppearanceScreen(settings: backend.settings) }
}

/// The You tab shows the citizen's picture at 26 pt with an accent ring when selected (iOS design §3).
/// Until signing in arrives (PR #2) it is a neutral person on the paper tint.
@MainActor
enum YouTabIcon {
    static func image(selected: Bool, style: UIUserInterfaceStyle) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let circle = UIBezierPath(ovalIn: rect)
            DLPalette.userATint.value(for: style).uiColor.setFill()
            circle.fill()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let person = UIImage(systemName: "person.fill", withConfiguration: symbolConfig)?
                .withTintColor(DLPalette.inkQuiet.value(for: style).uiColor, renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size.width - person.size.width) / 2, y: (size.height - person.size.height) / 2 + 1)
                person.draw(at: origin)
            }

            let ring = UIBezierPath(ovalIn: selected ? rect.insetBy(dx: 0.75, dy: 0.75) : rect.insetBy(dx: 0.25, dy: 0.25))
            ring.lineWidth = selected ? 1.5 : 0.5
            (selected ? DLPalette.seal : DLPalette.line).value(for: style).uiColor.setStroke()
            ring.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
