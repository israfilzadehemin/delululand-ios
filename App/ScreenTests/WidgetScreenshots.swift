import DLDesignSystem
import DLI18n
import DLTestSupport
import DLWidgets
import SwiftUI
import Testing
import UIKit

/// Every widget size × state (doc "Delululand — iPad Layout" WG13; iOS canvas Y-Widget-sizes,
/// Selfies canvas W-States), light, dark and Persian, on a Home Screen-like backdrop.
@MainActor
@Suite("Widget screenshots", .serialized, .enabled(if: !Shoot.onIPad && !Shoot.onDuo))
struct WidgetScreenshots {
    private let now = Date()

    /// A stand-in doodle: a sun, a wave and a heart on clear background.
    private var doodle: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).pngData { ctx in
            let c = ctx.cgContext
            c.setLineWidth(10)
            c.setLineCap(.round)
            c.setStrokeColor(UIColor(red: 0.85, green: 0.65, blue: 0.2, alpha: 1).cgColor)
            c.strokeEllipse(in: CGRect(x: 40, y: 40, width: 70, height: 70))
            c.setStrokeColor(UIColor(red: 0.4, green: 0.55, blue: 0.47, alpha: 1).cgColor)
            c.move(to: CGPoint(x: 30, y: 230))
            c.addLines(between: [CGPoint(x: 30, y: 230), CGPoint(x: 130, y: 170), CGPoint(x: 230, y: 220), CGPoint(x: 370, y: 180)])
            c.strokePath()
            c.setStrokeColor(UIColor(red: 0.7, green: 0.23, blue: 0.23, alpha: 1).cgColor)
            c.strokeEllipse(in: CGRect(x: 250, y: 60, width: 60, height: 50))
        }
    }

    /// A stand-in selfie: a face-ish disc on a warm or cool wash.
    private func photo(_ hue: CGFloat) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
            UIColor(hue: 0.07, saturation: 0.3, brightness: 0.95, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 70, y: 50, width: 100, height: 120)).fill()
            UIColor(white: 0.2, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 50, y: 160, width: 140, height: 120)).fill()
        }
    }

    private func data(mine: SelfieSlot = .none, theirs: SelfieSlot = .none, board: Bool = true, boardMine: Bool = false) -> WidgetData {
        var d = WidgetData.sample(now: now)
        d.board = board ? WidgetBoard(image: doodle, mine: boardMine, authorName: boardMine ? "Emin" : "Leyla", createdAt: now.addingTimeInterval(-7200), isNew: !boardMine) : nil
        d.mine = mine
        d.theirs = theirs
        return d
    }

    private var mineSlot: SelfieSlot { .photo(photo(0.05), takenAt: now.addingTimeInterval(-18000), expiresAt: now.addingTimeInterval(68400)) }
    private var theirsSlot: SelfieSlot { .photo(photo(0.55), takenAt: now.addingTimeInterval(-10800), expiresAt: now.addingTimeInterval(75600)) }
    private var lockedSlot: SelfieSlot { .locked(blur: photo(0.55), takenAt: now.addingTimeInterval(-10800), expiresAt: now.addingTimeInterval(75600)) }

    private func tile<V: View>(_ size: CGSize, _ face: V, margins: Bool = true) -> some View {
        face
            .padding(margins ? 14 : 0)
            .frame(width: size.width, height: size.height)
            .background(Color.dlPaper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private static let small = CGSize(width: 158, height: 158)
    private static let medium = CGSize(width: 338, height: 158)
    private static let large = CGSize(width: 338, height: 354)
    private static let rectangular = CGSize(width: 172, height: 76)

    private var page: some View {
        VStack(spacing: 18) {
            HStack(spacing: 22) {
                tile(Self.small, BoardWidgetView(data: data(), date: now, size: .small))
                tile(Self.small, BoardWidgetView(data: data(boardMine: true), date: now, size: .small))
            }
            tile(Self.large, BoardWidgetView(data: data(), date: now, size: .large))
            tile(Self.medium, SelfiesWidgetView(data: data(mine: mineSlot, theirs: theirsSlot), date: now, size: .medium), margins: false)
            tile(Self.medium, SelfiesWidgetView(data: data(theirs: lockedSlot), date: now, size: .medium), margins: false)
            tile(Self.medium, SelfiesWidgetView(data: data(), date: now, size: .medium), margins: false)
            HStack(spacing: 22) {
                tile(Self.small, SelfiesWidgetView(data: data(theirs: lockedSlot), date: now, size: .small), margins: false)
                tile(Self.small, SelfiesWidgetView(data: data(mine: mineSlot), date: now, size: .small), margins: false)
            }
            tile(Self.medium, ClocksWidgetView(data: data(), date: now, size: .medium))
            HStack(spacing: 22) {
                ClocksWidgetView(data: data(), date: now, size: .rectangular)
                    .padding(8)
                    .frame(width: Self.rectangular.width, height: Self.rectangular.height)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                tile(Self.small, BoardWidgetView(data: .signedOut, date: now, size: .small))
            }
            HStack(spacing: 22) {
                tile(Self.small, SelfiesWidgetView(data: .signedOut, date: now, size: .small), margins: false)
                tile(Self.small, ClocksWidgetView(data: .signedOut, date: now, size: .medium))
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.85, green: 0.78, blue: 0.70), Color(red: 0.43, green: 0.5, blue: 0.6)], startPoint: .top, endPoint: .bottom))
    }

    @Test func widgetsLight() {
        Shoot.page(page, named: "widgets-light", style: .light, height: 1900)
    }

    @Test func widgetsDark() {
        Shoot.page(page, named: "widgets-dark", style: .dark, height: 1900)
    }

    @Test func widgetsFa() {
        I18n.shared.set(.fa)
        Shoot.page(page.environment(\.layoutDirection, .rightToLeft), named: "widgets-fa-light", style: .light, height: 1900)
        I18n.shared.set(.en)
    }
}
