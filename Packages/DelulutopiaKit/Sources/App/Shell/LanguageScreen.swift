import DLData
import DLDesignSystem
import DLI18n
import DLUI
import SwiftUI

/// You › Language (doc "Delululand — Languages" L6, L8; web `LanguageScreen`): each language named in its
/// own words. A pick applies at once and is saved to the account, so every device and every notification
/// follows it; if the save is refused the old language comes back with a notice in that language.
public struct LanguageScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @State private var busy = false

    public init() {}

    public var body: some View {
        let current = I18n.shared.lang
        List {
            Section {
                ForEach(Lang.allCases, id: \.self) { lang in
                    Button { pick(lang) } label: {
                        DLCheckRow(lang.native, checked: current == lang)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityAddTraits(current == lang ? .isSelected : [])
                    .dlListRow()
                }
            } footer: {
                Text(t("settings.languageNote"))
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
            }
        }
        .dlGroupedList()
        .navigationTitle(t("settings.language"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(_ lang: Lang) {
        let before = I18n.shared.lang
        guard lang != before, !busy else { return }
        I18n.shared.set(lang)
        busy = true
        Task {
            do {
                try await backend.api.setLanguage(lang)
            } catch {
                I18n.shared.set(before)
                notice(.text(translate(before, "settings.languageNotSaved")))
            }
            busy = false
        }
    }
}
