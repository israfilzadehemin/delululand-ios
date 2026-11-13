import SwiftUI

/// The coloured square behind a settings symbol (30 pt, 8 pt corners, white symbol).
public struct DLRowIcon: View {
    let symbol: String
    let tint: Color

    public init(_ symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An inset-grouped row's content: optional icon, title (16/500), optional subtitle (13, quiet).
public struct DLRowLabel: View {
    let title: String
    let subtitle: String?
    let icon: DLRowIcon?

    public init(_ title: String, subtitle: String? = nil, icon: DLRowIcon? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let icon {
                icon
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .dlText(.callout)
                    .foregroundStyle(.dlInk)
                if let subtitle {
                    Text(subtitle)
                        .dlText(.footnote)
                        .foregroundStyle(.dlInkQuiet)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
    }
}

/// A choice row with a checkmark (Appearance: Light / Dark / Match device).
public struct DLCheckRow: View {
    let title: String
    let subtitle: String?
    let checked: Bool

    public init(_ title: String, subtitle: String? = nil, checked: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.checked = checked
    }

    public var body: some View {
        HStack(spacing: 12) {
            DLRowLabel(title, subtitle: subtitle)
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.dlSeal)
                .opacity(checked ? 1 : 0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
    }
}

/// A card that groups rows outside a `List` (24 pt corners, hairline dividers inset 16 pt).
public struct DLGroupedCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(.dlCell, in: RoundedRectangle(cornerRadius: DLRadius.groupedCard, style: .continuous))
    }
}

/// One row inside a `DLGroupedCard`; every row but the first draws the hairline above it.
public struct DLGroupedCardRow<Content: View>: View {
    let divider: Bool
    let content: Content

    public init(divider: Bool = true, @ViewBuilder content: () -> Content) {
        self.divider = divider
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .overlay(alignment: .top) {
                if divider {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
    }
}

public extension View {
    /// Inset-grouped list on paper with cell-coloured rows (iOS canvas Components).
    func dlGroupedList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.dlPaper)
    }

    /// A list row on the grouped cell colour.
    func dlListRow() -> some View {
        listRowBackground(Color.dlCell)
    }
}
