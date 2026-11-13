import DLData
import DLDesignSystem
import DLNetwork
import SwiftUI
import UIKit

/// Decoded images by URL. Media on the API needs the session cookie, so images load through the
/// API client rather than `AsyncImage`.
public final class ImageCache: @unchecked Sendable {
    public static let shared = ImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 120 * 1024 * 1024
        return c
    }()

    public func image(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    public func store(_ image: UIImage, _ key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Loads `path` with the session cookie, decoded and scaled down to `maxPixel` on its longer side.
    public func load(_ path: String, client: APIClient, maxPixel: CGFloat = 1600) async -> UIImage? {
        let key = "\(path)#\(Int(maxPixel))"
        if let hit = image(key) { return hit }
        let request = client.makeRequest("GET", path)
        guard let data = try? await client.data(for: request) else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(data: data) else { return nil }
            let longer = max(image.size.width, image.size.height) * image.scale
            if longer > maxPixel {
                let ratio = maxPixel / longer
                let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
                return image.preparingThumbnail(of: size) ?? image
            }
            return image.preparingForDisplay() ?? image
        }.value
        if let decoded { store(decoded, key) }
        return decoded
    }
}

/// An image from the API (attachments, avatars, stamps, the board).
public struct RemoteImage<Placeholder: View>: View {
    let path: String?
    let contentMode: ContentMode
    let maxPixel: CGFloat
    let placeholder: Placeholder
    @Environment(Backend.self) private var backend
    @State private var loaded: UIImage?
    @State private var loadedPath: String?

    public init(_ path: String?, contentMode: ContentMode = .fill, maxPixel: CGFloat = 1600, @ViewBuilder placeholder: () -> Placeholder) {
        self.path = path
        self.contentMode = contentMode
        self.maxPixel = maxPixel
        self.placeholder = placeholder()
    }

    private var cached: UIImage? {
        guard let path else { return nil }
        return ImageCache.shared.image("\(path)#\(Int(maxPixel))")
    }

    public var body: some View {
        Group {
            if let image = (loadedPath == path ? loaded : nil) ?? cached {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: path) {
            guard let path, cached == nil else { return }
            let image = await ImageCache.shared.load(path, client: backend.client, maxPixel: maxPixel)
            loaded = image
            loadedPath = path
        }
    }
}

public extension RemoteImage where Placeholder == Color {
    init(_ path: String?, contentMode: ContentMode = .fill, maxPixel: CGFloat = 1600) {
        self.init(path, contentMode: contentMode, maxPixel: maxPixel) { Color.dlPlaceholder }
    }
}

/// A citizen's picture from the API, or their initials on their signature tint.
public struct DLRemoteAvatar: View {
    let url: String?
    let name: String
    let size: CGFloat
    let signature: DLAvatar.Signature
    let ring: Bool

    public init(url: String?, name: String, size: CGFloat = 40, signature: DLAvatar.Signature = .neutral, ring: Bool = false) {
        self.url = url
        self.name = name
        self.size = size
        self.signature = signature
        self.ring = ring
    }

    public var body: some View {
        if let url {
            DLAvatar(
                initials: String(name.prefix(1)),
                image: nil,
                size: size,
                signature: signature,
                ring: ring
            )
            .overlay {
                RemoteImage(url, maxPixel: size * 3) { Color.clear }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
            .overlay(Circle().strokeBorder(ringColor, lineWidth: ring ? 2 : 1))
        } else {
            DLAvatar(initials: String(name.prefix(1)), size: size, signature: signature, ring: ring)
        }
    }

    private var ringColor: Color {
        switch signature {
        case .a: .dlUserA
        case .b: .dlUserB
        case .neutral: .dlLine
        }
    }
}

/// Citizens wear their universe's order: the first terracotta, the second sage (Z-Tokens).
public func signature(forIndex index: Int) -> DLAvatar.Signature {
    index == 0 ? .a : .b
}
