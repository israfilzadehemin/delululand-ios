import DLNetwork
import Foundation
import LocalAuthentication
import Observation
import Security

/// One door to the server for every screen (Android `Backend`): the API, live updates, the session,
/// Home's payload, this device's settings and the Face ID vault. Injected with
/// `.environment(backend)`.
@MainActor
@Observable
public final class Backend {
    public let config: AppConfig
    public let client: APIClient
    public let api: API
    public let live: LiveUpdates
    public let session: SessionStore
    public let home: HomeStore
    public let settings: DeviceSettings
    public let biometrics: BiometricVault
    /// `GET /api/config`: shortened timers on test servers (the TEST banner).
    public private(set) var server: ServerSettings?
    /// A PIN just typed at sign-in, waiting for the signed-in app to offer Face ID once (X1).
    public var pendingBiometricOffer: PendingBiometricOffer?

    public init(
        config: AppConfig,
        settings: DeviceSettings,
        cookies: CookieStore? = nil,
        biometrics: BiometricVault? = nil,
        protocolClasses: [AnyClass] = []
    ) {
        self.config = config
        self.settings = settings
        let client = APIClient(
            baseURL: config.apiBaseURL,
            cookies: cookies ?? CookieStore(service: "com.delulutopia.cookies.\(config.environment.rawValue)"),
            userAgent: "Delulutopia-iOS/\(config.version) (\(config.build))",
            protocolClasses: protocolClasses
        )
        self.client = client
        let api = API(client: client)
        self.api = api
        let live = LiveUpdates(client: client)
        self.live = live
        self.session = SessionStore(api: api)
        self.home = HomeStore(api: api, live: live)
        self.biometrics = biometrics ?? BiometricVault(service: "com.delulutopia.pin.\(config.environment.rawValue)")
    }

    public func loadServerSettings() async {
        server = try? await api.config()
    }

    /// The TEST line: shown on every screen while the API runs shortened timers.
    public var testBanner: String? {
        guard let s = server, s.testTiming else { return nil }
        var line = "TEST · DELAY \(DLTime.durationText(s.delay)) · WINDOW \(DLTime.durationText(s.window))"
        if let d = s.discussionDelay { line += " · DISCUSSIONS \(DLTime.durationText(d))" }
        return line
    }

    /// Absolute URL of an API media path.
    public func url(_ path: String) -> URL { client.url(path) }

    /// Throttle answers (`CODE_THROTTLED`, `PIN_THROTTLED`) are invisible: wait as told (at most 2 s)
    /// and resubmit once; a second one surfaces like a wrong key or PIN, as on the web.
    public func retryingThrottle<T: Sendable>(_ throttleCode: String, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as APIError where error.code == throttleCode {
            let wait = Double(min(error.retryAfterMs ?? 1000, 2000) + 50) / 1000
            try? await Task.sleep(for: .seconds(wait))
            return try await operation()
        }
    }

    /// Signed in: start Home and the live stream (foreground only; the app scene calls `pause`).
    public func didSignIn() {
        live.start()
        home.start()
    }

    public func didSignOut() {
        live.stop()
        home.stop()
    }
}

public struct PendingBiometricOffer: Equatable, Sendable {
    public let userId: Int
    public let pin: String

    public init(userId: Int, pin: String) {
        self.userId = userId
        self.pin = pin
    }
}

/// Face ID unlock (iOS design §6, decision D8; Android B2): after one PIN entry the PIN is kept in a
/// Keychain item that only opens with the biometry enrolled now (`.biometryCurrentSet`). Unlocking
/// reads it behind the system Face ID prompt and submits it. Enrolling a new face invalidates it: the
/// PIN is asked again and the offer comes back. No API change.
public final class BiometricVault: Sendable {
    public enum Kind: Sendable {
        case faceID, touchID, none
    }

    private let service: String

    public init(service: String) {
        self.service = service
    }

    /// What this device offers (Face ID on iPhone, Touch ID on iPhone Duo and iPad).
    public var kind: Kind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    public var isAvailable: Bool { kind != .none }

    private func account(userId: Int) -> String { "user-\(userId)" }

    public func hasPin(userId: Int) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(userId: userId),
            kSecUseAuthenticationContext as String: context,
            kSecReturnAttributes as String: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Any citizen enrolled on this device (the You › Account switch).
    public func isEnabled(userId: Int) -> Bool { hasPin(userId: userId) }

    @discardableResult
    public func store(pin: String, userId: Int) -> Bool {
        remove(userId: userId)
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil) else {
            return false
        }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(userId: userId),
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(pin.utf8),
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Shows the system biometry prompt and returns the PIN, or nil (cancelled, failed, invalidated).
    public func pin(userId: Int, reason: String) async -> String? {
        let service = self.service
        let account = account(userId: userId)
        return await Task.detached {
            let context = LAContext()
            context.localizedReason = reason
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }

    public func remove(userId: Int) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(userId: userId),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
