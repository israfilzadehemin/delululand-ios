import DLData
import DLDesignSystem
import SwiftUI
import UIKit

/// The floating glass tab bar on iOS 26+ (the system draws it), the classic bar before. Each tab
/// keeps its own navigation stack.
struct MainTabView: View {
    @Binding var selection: AppTab
    let config: AppConfig
    let settings: DeviceSettings
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    root(for: tab)
                }
                .tabItem { tabLabel(tab) }
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .you:
            YouScreen(config: config, settings: settings)
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
