import DLDesignSystem
import DLI18n
import SwiftUI

/// L6 (web i18n/LangSwitch; Android `LangSwitch`): "English · Azərbaycanca · فارسی" under the key form
/// and on the cards screen. A pick applies at once, is remembered on this device and goes with create or
/// join, so the new citizen starts in it.
struct LangSwitch: View {
    var body: some View {
        let current = I18n.shared.lang
        HStack(spacing: 0) {
            ForEach(Array(Lang.allCases.enumerated()), id: \.element) { i, lang in
                if i > 0 {
                    Text(verbatim: "·").dlText(.footnote).foregroundStyle(.dlInkQuiet).accessibilityHidden(true)
                }
                Button { I18n.shared.set(lang) } label: {
                    Text(verbatim: lang.native)
                        .font(.custom(lang == current ? DLFontName.manropeBold.name : DLFontName.manropeMedium.name, size: 13, relativeTo: .footnote))
                        .foregroundStyle(lang == current ? Color.dlInk : Color.dlInkQuiet)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(lang == current ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("settings.language"))
    }
}
