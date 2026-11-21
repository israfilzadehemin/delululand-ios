import DLWidgets
import SwiftUI
import WidgetKit

/// The Home Screen and Lock Screen widgets (doc "Delululand — iPad Layout" WG1): the board, today's
/// selfies, and both clocks with moods. Faces, loader and timeline live in the package (DLWidgets).
@main
struct DelulutopiaWidgets: WidgetBundle {
    var body: some Widget {
        DLBoardWidget()
        DLSelfiesWidget()
        DLClocksWidget()
    }
}
