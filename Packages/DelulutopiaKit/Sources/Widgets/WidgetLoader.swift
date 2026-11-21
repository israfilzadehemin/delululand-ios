import DLI18n
import DLNetwork
import Foundation
import UIKit

/// Loads the widgets' data in the extension (WG2): Home with the app's session, read-only from the
/// shared keychain group, then the doodle and the selfies the citizen may see, scaled down. The last
/// good answer is kept in the extension's own defaults, so a widget offline keeps what it showed.
public enum WidgetLoader {
    private static let cacheKey = "dl.widget.last"

    public static func load() async -> WidgetData {
        guard let (api, client) = session() else { return .signedOut }
        do {
            let home = try await api.home()
            if let lang = home.me.language.flatMap(Lang.init(rawValue:)) { I18n.shared.set(lang) }
            async let board = image(home.board?.url, client: client, maxPixel: 900)
            async let mine = image(home.selfies?.mine?.url, client: client, maxPixel: 500)
            let theirsURL = home.selfies?.theirs.flatMap { s in s.locked || home.selfies?.mine == nil ? nil : s.url }
            async let theirs = image(theirsURL, client: client, maxPixel: 500)
            let data = await WidgetMapping.make(home: home, boardImage: board, mineImage: mine, theirsImage: theirs)
            save(data)
            return data
        } catch let error as APIError where error.status == 401 || error.status == 403 {
            return .signedOut
        } catch {
            return cached() ?? .signedOut
        }
    }

    /// The app's server and session: the same Info.plist keys and keychain service the app uses.
    static func session() -> (API, APIClient)? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let raw = info["DLApiBaseURL"] as? String, let base = URL(string: raw), base.scheme == "https",
              let environment = info["DLEnvironment"] as? String, ["staging", "prod"].contains(environment)
        else { return nil }
        let group = (info["DLKeychainGroup"] as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 }
        let cookies = CookieStore(service: "com.delulutopia.cookies.\(environment)", accessGroup: group, readOnly: true)
        guard !cookies.names.isEmpty else { return nil }
        let client = APIClient(baseURL: base, cookies: cookies, userAgent: "Delulutopia-iOS-Widgets")
        return (API(client: client), client)
    }

    private static func image(_ path: String?, client: APIClient, maxPixel: CGFloat) async -> Data? {
        guard let path else { return nil }
        guard let data = try? await client.data(for: client.makeRequest("GET", path)), let image = UIImage(data: data) else { return nil }
        let longer = max(image.size.width, image.size.height) * image.scale
        let scaled: UIImage
        if longer > maxPixel {
            let ratio = maxPixel / longer
            scaled = image.preparingThumbnail(of: CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)) ?? image
        } else {
            scaled = image
        }
        // PNG keeps the doodle's transparency and line edges; selfies are JPEG.
        return path.contains("selfie") ? scaled.jpegData(compressionQuality: 0.85) : scaled.pngData()
    }

    private static func save(_ data: WidgetData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }

    private static func cached() -> WidgetData? {
        guard let raw = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: raw)
    }
}
