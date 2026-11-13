import DLDesignSystem
import DLUI
import SwiftUI

/// A tab root that PR #2 replaces with the real screen.
struct PlaceholderScreen: View {
    let tab: AppTab

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.dlInkQuiet)
                    .dlEnter(.pop)
                Text(tab.placeholderLine)
                    .dlText(.callout)
                    .foregroundStyle(.dlInkQuiet)
                    .multilineTextAlignment(.center)
                    .dlEnter(.rise, delay: 0.08)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 120)
        }
        .background(.dlPaper)
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
