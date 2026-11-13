import DLDesignSystem
import DLTestSupport
import SwiftUI
import Testing

/// The component catalog in light and dark, published to `ci-screenshots` for review. The tall page
/// is drawn off screen, so the glass pieces get their own on-screen shot.
@MainActor
@Suite("Catalog screenshots", .serialized)
struct CatalogScreenshots {
    @Test func catalogLight() {
        Shoot.page(DLComponentCatalog(), named: "catalog-light", style: .light, height: 2300)
    }

    @Test func catalogDark() {
        Shoot.page(DLComponentCatalog(), named: "catalog-dark", style: .dark, height: 2300)
    }

    @Test func glassLight() {
        Shoot.screen(DLGlassSamples(), named: "glass-light", style: .light)
    }

    @Test func glassDark() {
        Shoot.screen(DLGlassSamples(), named: "glass-dark", style: .dark)
    }
}
