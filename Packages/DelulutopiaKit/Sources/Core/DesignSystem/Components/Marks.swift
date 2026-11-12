import SwiftUI

/// The terracotta NEW pill (letters, board ribbon, "2 new").
public struct DLNewBadge: View {
    let text: String

    public init(_ text: String = "New") {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .dlText(.pill)
            .foregroundStyle(.dlOnNewBadge)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.dlNewBadge, in: Capsule())
    }
}

/// The lavender SOON chip on menu items that are not available yet.
public struct DLSoonChip: View {
    public init() {}

    public var body: some View {
        Text("Soon")
            .dlText(.pill)
            .foregroundStyle(.dlSeal)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.dlSealTint, in: Capsule())
    }
}

/// A countdown chip with tabular digits (28:41; the colour carries the urgency, not the format).
public struct DLCountdownChip: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .dlText(.countdown)
        }
        .foregroundStyle(.dlInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.dlCountdownChip, in: Capsule())
    }
}

/// The navy "new" dot on tabs and compose buttons (9 pt with a 2 pt halo).
public struct DLNewDot: View {
    let halo: Color

    public init(halo: Color = .dlPaper) {
        self.halo = halo
    }

    public var body: some View {
        Circle()
            .fill(.dlSeal)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(halo, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// A citizen's picture, or their initials on their signature tint.
public struct DLAvatar: View {
    public enum Signature: Sendable {
        /// The universe creator (terracotta).
        case a
        /// The other citizen (sage).
        case b
        case neutral
    }

    let initials: String
    let image: Image?
    let size: CGFloat
    let signature: Signature
    let ring: Bool

    public init(initials: String, image: Image? = nil, size: CGFloat = 40, signature: Signature = .neutral, ring: Bool = false) {
        self.initials = initials
        self.image = image
        self.size = size
        self.signature = signature
        self.ring = ring
    }

    private var tint: Color {
        switch signature {
        case .a: .dlUserATint
        case .b: .dlUserBTint
        case .neutral: .dlPaperLetter
        }
    }

    private var ringColor: Color {
        switch signature {
        case .a: .dlUserA
        case .b: .dlUserB
        case .neutral: .dlLine
        }
    }

    public var body: some View {
        ZStack {
            Circle().fill(tint)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials.uppercased())
                    .font(.custom(DLFontName.manropeExtraBold.rawValue, fixedSize: size * 0.38))
                    .foregroundStyle(.dlInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ringColor, lineWidth: ring ? 2 : 1))
        .accessibilityHidden(true)
    }
}
