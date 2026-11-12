import DLData
import DLDesignSystem
import SwiftUI
import UIKit

/// Keys and invites are typed and shown as XXXX-XXXX-XXXX; the server ignores case, spaces and hyphens.
public func groupKey(_ value: String) -> String {
    var kept = ""
    for scalar in value.unicodeScalars where scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
        kept.unicodeScalars.append(scalar)
    }
    let upper = kept.uppercased().prefix(12)
    var groups: [String] = []
    var current = ""
    for c in upper {
        current.append(c)
        if current.count == 4 {
            groups.append(current)
            current = ""
        }
    }
    if !current.isEmpty { groups.append(current) }
    return groups.joined(separator: "-")
}

/// "iPhone" or "iPad", for copy that names this device (iOS design §7).
@MainActor
public var deviceWord: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
}

/// The TEST line on every screen while the API runs shortened timers (web `.dl-test-banner`).
public struct DLTestBanner: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .dlText(.pill)
            .foregroundStyle(.dlOnSeal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(.dlSeal)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// A red note under a form or above a list (web `.dl-banner`).
public struct DLErrorNote: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .dlText(.footnote)
            .foregroundStyle(.dlInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.dlErrorTint, in: RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous).strokeBorder(.dlErrorLine, lineWidth: 1))
    }
}

/// A link in the web's strong style: ink, bold, underlined ("Create a universe").
public struct DLStrongLink: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(DLFontName.manropeBold.rawValue, size: 14, relativeTo: .subheadline))
                .underline()
                .foregroundStyle(.dlInk)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A toast host: `.dlToast($toast)` shows a glass capsule above the tab bar for a few seconds.
public struct DLToastItem: Equatable, Identifiable {
    public let id = UUID()
    public let text: String
    public let symbol: String?
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(_ text: String, symbol: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
    }

    public static func == (a: DLToastItem, b: DLToastItem) -> Bool { a.id == b.id }
}

private struct DLToastHost: ViewModifier {
    @Binding var item: DLToastItem?
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let item {
                DLToast(item.text, symbol: item.symbol, actionTitle: item.actionTitle, action: item.action.map { act in
                    { act(); self.item = nil }
                })
                .padding(.horizontal, 16)
                .padding(.bottom, bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: item.id) {
                    try? await Task.sleep(for: .seconds(item.action == nil ? 3 : 5))
                    if self.item?.id == item.id {
                        withAnimation(DLMotion.easeIn(0.2)) { self.item = nil }
                    }
                }
            }
        }
        .animation(DLMotion.easeOut(0.28), value: item)
    }
}

public extension View {
    func dlToast(_ item: Binding<DLToastItem?>, bottom: CGFloat = 12) -> some View {
        modifier(DLToastHost(item: item, bottom: bottom))
    }
}

/// "Can't reach <universe>. Try again." with a Try again button (offline states).
public struct DLUnreachable: View {
    let universe: String
    let retry: () -> Void

    public init(universe: String, retry: @escaping () -> Void) {
        self.universe = universe
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.dlInkQuiet)
            Text("Can’t reach \(universe). Try again.")
                .dlText(.callout)
                .foregroundStyle(.dlError)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.dlFilled)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
