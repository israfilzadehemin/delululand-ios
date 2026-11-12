import DLData
import FeatureHome
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
        case .you:
            YouScreen(config: backend.config, settings: backend.settings)
        default:
            PlaceholderScreen(tab: tab)
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: AppTab) -> some View {
        if tab == .you {
            Label {
                Text(tab.title)
            } icon: {
                Image(uiImage: YouTabIcon.image(selected: selection == .you, style: colorScheme == .dark ? .dark : .light))
            }
        } else {
            Label(tab.title, systemImage: tab.symbol)
        }
    }
}

/// A pushed screen for a route. Screens that have not landed yet show the placeholder line.
struct RouteScreen: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .appearance:
            AppearanceScreenHost()
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
