import SwiftUI

/// The zoom transition (iOS 18+): a full-screen cover grows out of the view it came from, and shrinks
/// back into it on close (board tile → pad / viewer; doc "Delululand — Board" F2). iOS 17 keeps the
/// system's slide-up.
public extension View {
    /// Marks the view a cover zooms out of.
    @ViewBuilder
    func dlZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Put on the cover's content: it zooms from the source with the same id.
    @ViewBuilder
    func dlZoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
