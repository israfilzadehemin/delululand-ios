import DLDesignSystem
import DLTestSupport
import SwiftUI
import Testing

/// The component catalog in light and dark, published to `ci-screenshots` for review.
@MainActor
@Suite("Catalog screenshots", .serialized)
struct CatalogScreenshots {
    @Test func catalogLight() {
        Shoot.page(DLComponentCatalog(), named: "catalog-light", style: .light, height: 2300)
    }

    @Test func catalogDark() {
        Shoot.page(DLComponentCatalog(), named: "catalog-dark", style: .dark, height: 2300)
    }
}
