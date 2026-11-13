import DLDesignSystem
import DLI18n
import SwiftUI

/// L6, L20 (web i18n/LangSwitch; Android `LangSwitch`): one quiet button under the key form and on the
/// cards screen, a globe and the language in force in its own words, opening a menu of all five, each in
/// its own words (five names no longer fit one row). A pick applies at once, is remembered on this device
/// and goes with create or join, so the new citizen starts in it.
struct LangSwitch: View {
    /// The button's name for every reader before their language is known: "Language" in all five.
    private static let label = "Language · Dil · زبان · Язык"

    var body: some View {
        let current = I18n.shared.lang
        Menu {
            Picker(selection: Binding(get: { I18n.shared.lang }, set: { I18n.shared.set($0) })) {
                ForEach(Lang.allCases, id: \.self) { lang in
                    Text(verbatim: lang.native).tag(lang)
                }
            } label: {
                Text(verbatim: Self.label)
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 14, weight: .regular)).accessibilityHidden(true)
                Text(verbatim: current.native)
                    .font(.custom(DLFontName.manropeMedium.name, size: 14, relativeTo: .footnote))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(Color.dlInkQuiet)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: "\(Self.label): \(current.native)"))
        .frame(maxWidth: .infinity)
    }
}
