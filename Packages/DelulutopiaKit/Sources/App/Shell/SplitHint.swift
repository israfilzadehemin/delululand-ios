import DLDesignSystem
import DLI18n
import DLUI
import SwiftUI

/// The iPad's detail column with nothing selected (iPad Layout IP4; canvas T-Letters-empty): the web
/// split's hint (`.dl-split-hint`), a dashed box with one quiet line. Nothing is opened on its own,
/// since opening a letter or a thread marks it read.
struct SplitHint: View {
    let tab: AppTab

    var body: some View {
        VStack {
            Text(line)
                .dlText(.callout)
                .foregroundStyle(.dlInkQuiet)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
                .padding(.horizontal, 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.dlLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 28)
                .padding(.top, 52)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dlPaper.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        switch tab {
        case .discussions: t("discussions.pickADiscussionToRead")
        case .emails: t("emails.pickAThreadToRead")
        default: t("letters.pickALetterToRead")
        }
    }
}
