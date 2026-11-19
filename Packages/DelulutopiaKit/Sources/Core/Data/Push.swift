import DLNetwork
import Foundation
import Observation
import UIKit
import UserNotifications

/// Where a notification (or iOS Settings' "Delulutopia Notification Settings" link) opens the app
/// (iOS design I-5). Built from the push's `url`, the same path the web opens.
public enum AppLink: Equatable, Sendable {
    case home
    case letters
    case letter(PublicID)
    case discussions
    case discussion(PublicID)
    case emails
    /// An email thread: email pushes carry the thread's id (Emails Q23).
    case thread(PublicID)
    /// You › Notifications (`providesAppNotificationSettings`).
    case notificationSettings

    /// `/letters/<id>`, `/discussions/<id>`, `/emails/<thread>`, the bare lists, anything else Home.
    public init(path: String?) {
        let parts = (path ?? "")
            .split(separator: "?").first.map(String.init).map { $0.split(separator: "/").map(String.init) } ?? []
        let id = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        switch (parts.first, id) {
        case let ("letters", id?): self = .letter(id)
        case ("letters", nil): self = .letters
        case let ("discussions", id?): self = .discussion(id)
        case ("discussions", nil): self = .discussions
        case let ("emails", id?): self = .thread(id)
        case ("emails", nil): self = .emails
        default: self = .home
        }
    }
}

/// iOS push (doc "Delululand — iOS Build" Q6, Q7; iOS design I-4, I-5): this device's permission,
/// its APNs token sent to the server while signed in (and removed before log-out), the app icon
/// badge, and the screen a tapped notification asks for. The in-app Notifications page stays the
/// source of truth for what is sent; iOS only decides whether this iPhone shows it.
@MainActor
@Observable
public final class PushStore {
    /// This device's notification permission, in the words Settings and Home use.
    public enum Permission: Equatable, Sendable {
        /// Not read yet.
        case unknown
        /// Never asked on this device: the app can show the system prompt.
        case notAsked
        case on
        /// Refused in the system prompt or switched off in iOS Settings: only Settings can turn it on.
        case blocked
    }

    public private(set) var permission: Permission = .unknown
    /// The APNs device token, hex, once iOS has given it.
    public private(set) var token: String?
    /// A notification tap waiting for the signed-in shell to open it (logged out: after the PIN).
    public var pendingLink: AppLink?

    private let api: API
    private let topic: String
    private let environment: String
    private let registerRemote: @MainActor () -> Void
    /// False in screenshot runs: the system is never asked, so no prompt, hint or badge appears.
    private let system: Bool
    private var signedIn = false
    private var sentToken: String?

    public static let askedKey = "dl.push.asked"

    public init(
        api: API,
        topic: String = Bundle.main.bundleIdentifier ?? "com.delulutopia.app",
        environment: String,
        system: Bool = true,
        registerRemote: @escaping @MainActor () -> Void = { UIApplication.shared.registerForRemoteNotifications() }
    ) {
        self.api = api
        self.topic = topic
        self.environment = environment
        self.system = system
        self.registerRemote = registerRemote
    }

    /// Whether the one-time ask (Home, after sign-in) has been shown on this device.
    public var asked: Bool {
        get { UserDefaults.standard.bool(forKey: Self.askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.askedKey) }
    }

    /// Reads the system permission; on, it (re)asks iOS for the token, which is sent when it comes.
    public func refreshPermission() async {
        guard system else { return }
        permission = Self.word(await Self.status())
        if permission == .on, signedIn { registerRemote() }
    }

    /// The system prompt (only iOS shows it, once). Blocked: nothing here can change it.
    @discardableResult
    public func requestPermission() async -> Bool {
        guard system else { return false }
        asked = true
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .providesAppNotificationSettings]
        await Self.ask(options)
        await refreshPermission()
        return permission == .on
    }

    /// iOS gave (or renewed) the token: send it now if signed in, else at sign-in.
    public func didRegister(tokenData: Data) {
        token = Self.hex(tokenData)
        Task { await upload() }
    }

    public func didSignIn() {
        signedIn = true
        sentToken = nil
        Task { await refreshPermission() }
    }

    /// Before the session ends (You › Log out): this install stops getting this citizen's pushes.
    public func willSignOut() async {
        if let token, sentToken != nil {
            try? await api.unregisterPushDevice(platform: "apns", token: token)
        }
        sentToken = nil
    }

    public func didSignOut() {
        signedIn = false
        sentToken = nil
        setBadge(0)
    }

    /// The app icon badge (Q7): the server sets it with each push, the app keeps it to the tab dots.
    public func setBadge(_ count: Int) {
        guard system else { return }
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
    }

    /// A tapped notification's `url`.
    public func open(path: String?) {
        pendingLink = AppLink(path: path)
    }

    private func upload() async {
        guard signedIn, let token, token != sentToken else { return }
        do {
            try await api.registerPushDevice(platform: "apns", token: token, appId: topic, environment: environment)
            sentToken = token
        } catch {
            // Sent again on the next start or sign-in; pushes wait until then.
        }
    }

    /// Read off the main actor: the settings object is not Sendable, its status is.
    nonisolated static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated static func ask(_ options: UNAuthorizationOptions) async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func word(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional, .ephemeral: .on
        case .denied: .blocked
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }
}
