import CryptoKit
import DLData
import DLDesignSystem
import SwiftUI
import UIKit
import WebKit

/// Stamps are SVG artwork served by the API (doc "Delululand — Stamps"); iOS has no public SVG
/// decoder, so each stamp is drawn once by an off-screen WebKit view and kept as a PNG (memory and
/// Caches). One render at a time.
@MainActor
public final class SVGRasterizer: NSObject, WKNavigationDelegate {
    public static let shared = SVGRasterizer()

    private let memory = NSCache<NSString, UIImage>()
    private var webView: WKWebView?
    private var busy = false
    private var loaded: CheckedContinuation<Void, Never>?

    private var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "stamps")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileName(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    public func cached(_ key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let url = directory.appending(path: fileName(key))
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: UIScreen.main.scale) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// The SVG drawn `width` points wide, its height from the viewBox.
    public func image(svg: Data, key: String, width: CGFloat) async -> UIImage? {
        let fullKey = "\(key)#\(Int(width))"
        if let hit = cached(fullKey) { return hit }
        while busy {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if let hit = cached(fullKey) { return hit }
        busy = true
        defer { busy = false }
        guard let image = await render(svg: svg, width: width) else { return nil }
        memory.setObject(image, forKey: fullKey as NSString)
        if let png = image.pngData() {
            try? png.write(to: directory.appending(path: fileName(fullKey)))
        }
        return image
    }

    private func viewBox(_ svg: String) -> CGSize {
        let pattern = #"viewBox\s*=\s*"[\d.\-]+\s+[\d.\-]+\s+([\d.]+)\s+([\d.]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
              let w = Range(m.range(at: 1), in: svg).flatMap({ Double(svg[$0]) }),
              let h = Range(m.range(at: 2), in: svg).flatMap({ Double(svg[$0]) }), w > 0, h > 0 else {
            return CGSize(width: 300, height: 380)
        }
        return CGSize(width: w, height: h)
    }

    private func render(svg data: Data, width: CGFloat) async -> UIImage? {
        let text = String(decoding: data, as: UTF8.self)
        let box = viewBox(text)
        let size = CGSize(width: width, height: (width * box.height / box.width).rounded())
        let web = webView(size: size)
        let html = """
        <html><head><meta name="viewport" content="width=\(Int(size.width)), initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        img{display:block;width:\(Int(size.width))px;height:\(Int(size.height))px}</style></head>
        <body><img src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
        """
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loaded = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
        try? await Task.sleep(for: .milliseconds(40))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.afterScreenUpdates = true
        return try? await web.takeSnapshot(configuration: config)
    }

    private func webView(size: CGSize) -> WKWebView {
        let web = webView ?? {
            let configuration = WKWebViewConfiguration()
            configuration.suppressesIncrementalRendering = true
            let w = WKWebView(frame: .zero, configuration: configuration)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.scrollView.backgroundColor = .clear
            w.scrollView.isScrollEnabled = false
            w.isUserInteractionEnabled = false
            w.navigationDelegate = self
            w.accessibilityElementsHidden = true
            webView = w
            return w
        }()
        // WebKit only paints a view that is in a window: keep it off screen in the key window.
        web.frame = CGRect(x: -4000, y: 0, width: size.width, height: size.height)
        if web.window == nil, let window = Self.keyWindow {
            window.insertSubview(web, at: 0)
        }
        return web
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume()
        loaded = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume()
        loaded = nil
    }
}

/// A stamp from the API, drawn from its SVG (letters, the stamp picker, tiles). Shows the paper tone
/// until it is ready.
public struct StampImage: View {
    let url: String?
    let name: String
    let width: CGFloat
    @Environment(Backend.self) private var backend
    @State private var image: UIImage?

    public init(url: String?, name: String, width: CGFloat) {
        self.url = url
        self.name = name
        self.width = width
    }

    public var body: some View {
        Group {
            if let image = image ?? url.flatMap({ SVGRasterizer.shared.cached("\($0)#\(Int(width * 2))") }) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.dlLetterEnvelopeTone)
                    .aspectRatio(300.0 / 380.0, contentMode: .fit)
            }
        }
        .frame(width: width)
        .accessibilityLabel("Stamp: \(name)")
        .task(id: url) {
            guard let url else { return }
            let renderWidth = width * 2
            if let hit = SVGRasterizer.shared.cached("\(url)#\(Int(renderWidth))") {
                image = hit
                return
            }
            guard let data = try? await backend.client.data(for: backend.client.makeRequest("GET", url)) else { return }
            image = await SVGRasterizer.shared.image(svg: data, key: url, width: renderWidth)
        }
    }
}

extension ShapeStyle where Self == Color {
    static var dlLetterEnvelopeTone: Color { DLPalette.letterEnvelope.color }
}
