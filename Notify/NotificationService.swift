import DLNetwork
import Foundation
import UserNotifications
import WidgetKit

/// Read Ticks TK2 on iOS: the server marks new-email pushes `mutable-content`, so iOS wakes this
/// extension even while the app is closed. It tells the API the email reached this phone
/// (`POST /api/emails/delivered`), so the sender sees ✓✓, and shows the notification unchanged.
/// It reads the app's cookie jar from the shared keychain group and never writes it.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private var deliver: ((UNNotificationContent) -> Void)?
    private var content: UNNotificationContent?
    private var task: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        deliver = contentHandler
        content = request.content
        guard let emailId = request.content.userInfo["emailId"] as? String, !emailId.isEmpty, let api = Self.api() else {
            finish()
            return
        }
        task = Task { [weak self] in
            // One try: if it fails, the app's next fetch of Home or the emails delivers it anyway.
            try? await api.emailsDelivered(ids: [emailId])
            self?.finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        task?.cancel()
        finish()
    }

    private func finish() {
        // A new email may come with a new mood, doodle or selfie on Home: the widgets look again (WG3).
        WidgetCenter.shared.reloadAllTimelines()
        guard let deliver, let content else { return }
        self.deliver = nil
        deliver(content)
    }

    /// The app's server and session: the same Info.plist keys and keychain service the app uses.
    private static func api() -> API? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let raw = info["DLApiBaseURL"] as? String, let base = URL(string: raw), base.scheme == "https",
              let environment = info["DLEnvironment"] as? String, ["staging", "prod"].contains(environment)
        else { return nil }
        let group = (info["DLKeychainGroup"] as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 }
        let cookies = CookieStore(service: "com.delulutopia.cookies.\(environment)", accessGroup: group, readOnly: true)
        guard !cookies.names.isEmpty else { return nil }
        return API(client: APIClient(baseURL: base, cookies: cookies, userAgent: "Delulutopia-iOS-Notify"))
    }
}
