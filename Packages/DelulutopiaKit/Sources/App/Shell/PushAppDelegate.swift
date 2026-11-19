import DLData
import UIKit
import UserNotifications

/// The app delegate for push (iOS Build Q6; iOS design I-4, I-5): hands the APNs token to the
/// backend, keeps notifications out of the way while the app is open (live updates and the in-app
/// notice already show arrivals), and turns a tap into the screen it names. A tap that cold-starts
/// the app arrives before the backend is attached; it waits here until it is.
@MainActor
public final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    public var backend: Backend? {
        didSet { flush() }
    }

    private var pendingToken: Data?
    private var pendingPath: String??
    private var pendingSettings = false

    override public init() {
        super.init()
    }

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let backend {
            backend.push.didRegister(tokenData: deviceToken)
        } else {
            pendingToken = deviceToken
        }
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No token (simulator without APNs, no network): live updates still run in the foreground.
    }

    // MARK: UNUserNotificationCenterDelegate

    /// In the foreground the live stream and the in-app notice cover it; only the badge changes.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.badge]
    }

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let path = response.notification.request.content.userInfo["url"] as? String
        await opened(path: path)
    }

    /// iOS Settings › Delulutopia › Notifications › "Delulutopia Notification Settings".
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor in self.openedSettings() }
    }

    private func opened(path: String?) {
        if let backend {
            backend.push.open(path: path)
        } else {
            pendingPath = .some(path)
        }
    }

    private func openedSettings() {
        if let backend {
            backend.push.pendingLink = .notificationSettings
        } else {
            pendingSettings = true
        }
    }

    private func flush() {
        guard let backend else { return }
        if let token = pendingToken {
            backend.push.didRegister(tokenData: token)
            pendingToken = nil
        }
        if let path = pendingPath {
            backend.push.open(path: path)
            pendingPath = nil
        }
        if pendingSettings {
            backend.push.pendingLink = .notificationSettings
            pendingSettings = false
        }
    }
}
