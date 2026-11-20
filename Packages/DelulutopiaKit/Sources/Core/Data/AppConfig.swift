import Foundation

/// Which server this build talks to (decision D6), read from the build's Info.plist, where the
/// xcconfig of the scheme ("Delulutopia Staging" or "Delulutopia") put it.
public struct AppConfig: Sendable, Equatable {
    public enum Environment: String, Sendable {
        /// test.delulutopia.com, "Delulutopia TST".
        case staging
        /// delulutopia.com.
        case prod
    }

    public static let stagingURL = URL(string: "https://test.delulutopia.com")!

    public let environment: Environment
    public let apiBaseURL: URL
    public let version: String
    public let build: String
    /// The APNs environment of this build's tokens (`DLApnsEnvironment`): `sandbox` for Debug builds
    /// run from Xcode, `production` for Release (TestFlight, App Store).
    public let apnsEnvironment: String
    /// `DLKeychainGroup`: the keychain group the app shares with its Notification Service Extension
    /// (Read Ticks TK2); nil keeps the cookie jar in the app's own group.
    public let keychainGroup: String?

    public init(
        environment: Environment, apiBaseURL: URL, version: String, build: String,
        apnsEnvironment: String = "production", keychainGroup: String? = nil
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.version = version
        self.build = build
        self.apnsEnvironment = apnsEnvironment
        self.keychainGroup = keychainGroup
    }

    /// Reads `DLEnvironment`, `DLApiBaseURL`, `DLApnsEnvironment`, `DLKeychainGroup`, `CFBundleShortVersionString` and `CFBundleVersion`.
    /// A missing or malformed entry falls back to staging, never to production.
    public init(info: [String: Any]) {
        let environment = (info["DLEnvironment"] as? String).flatMap(Environment.init(rawValue:)) ?? .staging
        let url = (info["DLApiBaseURL"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
        self.environment = url == nil ? .staging : environment
        self.apiBaseURL = url ?? Self.stagingURL
        self.version = info["CFBundleShortVersionString"] as? String ?? "0"
        self.build = info["CFBundleVersion"] as? String ?? "0"
        self.apnsEnvironment = (info["DLApnsEnvironment"] as? String) == "sandbox" ? "sandbox" : "production"
        self.keychainGroup = (info["DLKeychainGroup"] as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 }
    }

    public static func fromMainBundle() -> AppConfig {
        AppConfig(info: Bundle.main.infoDictionary ?? [:])
    }

    public var isStaging: Bool { environment == .staging }

    /// The cookie jar's keychain service; the Notification Service Extension reads the same one.
    public static func cookieService(_ environment: Environment) -> String {
        "com.delulutopia.cookies.\(environment.rawValue)"
    }
}
