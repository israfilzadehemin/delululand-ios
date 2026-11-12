import DLI18n
import Foundation
import os
import Security

/// A refusal from the API (Technical Design §5.1): `{ "code", "message", …extra }`. `message` is the
/// spec's user text, shown as is. `status` 0 means the server was not reached.
public struct APIError: Error, Sendable, Equatable, LocalizedError {
    public let status: Int
    public let code: String
    public let message: String
    public let extra: [String: JSONValue]

    public init(status: Int, code: String, message: String, extra: [String: JSONValue] = [:]) {
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra
    }

    public static let offlineCode = "OFFLINE"

    /// No answer, or a 5xx: the screen says "Can't reach <universe>. Try again."
    public var isOffline: Bool { status == 0 || status >= 500 }
    /// Throttle answers carry how long to wait before the one silent resubmit.
    public var retryAfterMs: Int? { extra["retryAfterMs"]?.int }
    public var errorDescription: String? { message }

    static func offline(_ message: String = t("common.cantReachServer")) -> APIError {
        APIError(status: 0, code: offlineCode, message: message)
    }

    /// Any error as an APIError (cancellation stays a `CancellationError` for callers that check).
    public static func from(_ error: Error) -> APIError {
        if let e = error as? APIError { return e }
        return .offline()
    }
}

public extension Notification.Name {
    /// FS-A13: a 401 `NO_SESSION` anywhere means the session is gone; the app returns to the start.
    static let dlSessionEnded = Notification.Name("dl.sessionEnded")
}

/// The API holds the only clock (Technical Design §3.1). Every response carries `X-Server-Time`;
/// `offset = serverTime − deviceTime` (median of the last five) keeps countdowns right on a phone
/// whose clock is minutes off.
public final class ServerClock: Sendable {
    public static let shared = ServerClock()

    private struct State {
        var samples: [Double] = []
        var offset: Double = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func record(serverEpochMs: Double, deviceEpochMs: Double = Date().timeIntervalSince1970 * 1000) {
        state.withLock { s in
            s.samples.append(serverEpochMs - deviceEpochMs)
            if s.samples.count > 5 { s.samples.removeFirst(s.samples.count - 5) }
            let sorted = s.samples.sorted()
            s.offset = sorted[sorted.count / 2]
        }
    }

    public var offsetMs: Double { state.withLock { $0.offset } }

    /// Server-aligned now.
    public var now: Date { Date().addingTimeInterval(offsetMs / 1000) }
}

/// The browser's cookie jar, on a phone (decision D7): the session (`__Host-dl`) and the entry pass
/// (`__Host-dl-entry`) are kept exactly as a browser keeps them, so the API needs no change. Held in
/// memory and written to the Keychain on every change; expired cookies are never sent.
public final class CookieStore: Sendable {
    private struct Stored: Codable {
        var name: String
        var value: String
        var expires: Double?
        var domain: String
        var path: String
        var secure: Bool
    }

    private let service: String
    private let accessGroup: String?
    private let cookies: OSAllocatedUnfairLock<[Stored]>

    /// `accessGroup` shares the jar with the widgets and the share extension (PR #5).
    public init(service: String = "com.delulutopia.cookies", accessGroup: String? = nil, inMemory: Bool = false) {
        self.service = service
        self.accessGroup = accessGroup
        self.cookies = OSAllocatedUnfairLock(initialState: inMemory ? [] : Self.load(service: service, accessGroup: accessGroup))
    }

    /// The `Cookie` header for a request to `url`, or nil.
    public func header(for url: URL) -> String? {
        let now = Date().timeIntervalSince1970
        let host = url.host() ?? ""
        let path = url.path().isEmpty ? "/" : url.path()
        let (pairs, pruned) = cookies.withLock { list -> ([String], Bool) in
            let before = list.count
            list.removeAll { ($0.expires ?? .infinity) <= now }
            let matching = list.filter { c in
                Self.domainMatches(host: host, domain: c.domain) && path.hasPrefix(c.path)
                    && (!c.secure || url.scheme == "https")
            }
            return (matching.map { "\($0.name)=\($0.value)" }, list.count != before)
        }
        if pruned { persist() }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    /// Stores the response's `Set-Cookie` headers.
    public func store(from response: HTTPURLResponse, url: URL) {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, let v = value as? String { fields[k] = v }
        }
        let incoming = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map { cookie in
            Stored(
                name: cookie.name, value: cookie.value, expires: cookie.expiresDate?.timeIntervalSince1970,
                domain: cookie.domain, path: cookie.path, secure: cookie.isSecure
            )
        }
        // A cookie the server cleared (`Max-Age=0`) may not come back from `HTTPCookie` at all: any
        // name in the raw header that did not parse into a live cookie is removed.
        let raw = fields.first { $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame }?.value ?? ""
        let named = Self.cookieNames(in: raw)
        let cleared = named.subtracting(incoming.map(\.name))
        guard !incoming.isEmpty || !cleared.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        cookies.withLock { list in
            list.removeAll { cleared.contains($0.name) }
            for cookie in incoming {
                list.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
                if let expires = cookie.expires, expires <= now { continue }
                list.append(cookie)
            }
        }
        persist()
    }

    /// `HTTPCookie`s for AVFoundation, which loads media itself (`AVURLAssetHTTPCookiesKey`).
    public func httpCookies(for url: URL) -> [HTTPCookie] {
        cookies.withLock { $0 }.compactMap { c in
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: c.name, .value: c.value, .domain: c.domain, .path: c.path,
            ]
            if c.secure { props[.secure] = "TRUE" }
            if let expires = c.expires { props[.expires] = Date(timeIntervalSince1970: expires) }
            return HTTPCookie(properties: props)
        }.filter { Self.domainMatches(host: url.host() ?? "", domain: $0.domain) }
    }

    public var names: [String] { cookies.withLock { $0.map(\.name) } }

    public func clear() {
        cookies.withLock { $0.removeAll() }
        persist()
    }

    /// Cookie names in a (possibly comma-joined) Set-Cookie header.
    static func cookieNames(in header: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|,\s*)([^=;,\s]+)="#) else { return [] }
        let range = NSRange(header.startIndex..., in: header)
        return Set(regex.matches(in: header, range: range).compactMap { match in
            Range(match.range(at: 1), in: header).map { String(header[$0]) }
        })
    }

    private static func domainMatches(host: String, domain: String) -> Bool {
        let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == d || host.hasSuffix("." + d)
    }

    // MARK: Keychain

    private func query() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "jar",
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    private func persist() {
        let persistent = cookies.withLock { $0.filter { $0.expires != nil } }
        guard let data = try? JSONEncoder().encode(persistent) else { return }
        let q = query()
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add.merge(update) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func load(service: String, accessGroup: String?) -> [Stored] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "jar",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([Stored].self, from: data)) ?? []
    }
}

/// One HTTP door to the API: `X-Requested-With: delululand` (the API's CSRF rule, §8.3), JSON, the
/// cookie jar, the server clock and the `{code, message}` refusals.
public final class APIClient: Sendable {
    public let baseURL: URL
    public let cookies: CookieStore
    public let clock: ServerClock
    let session: URLSession
    let userAgent: String

    /// `protocolClasses` lets tests serve fixtures (screenshots) without a server.
    public init(
        baseURL: URL,
        cookies: CookieStore,
        clock: ServerClock = .shared,
        userAgent: String = "Delulutopia-iOS",
        protocolClasses: [AnyClass] = []
    ) {
        self.baseURL = baseURL
        self.cookies = cookies
        self.clock = clock
        self.userAgent = userAgent
        let config = URLSessionConfiguration.default
        if !protocolClasses.isEmpty {
            config.protocolClasses = protocolClasses + (config.protocolClasses ?? [])
        }
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    /// Absolute URL of an API path (`/api/attachments/…`); absolute URLs pass through.
    public func url(_ path: String, query: [String: String] = [:]) -> URL {
        if path.hasPrefix("http"), let absolute = URL(string: path) { return absolute }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    /// A request carrying the API headers and the cookie jar.
    public func makeRequest(_ method: String, _ path: String, query: [String: String] = [:]) -> URLRequest {
        let url = url(path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("delululand", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // L8: server-worded text (errors, moods, stamps) comes back in the citizen's language.
        request.setValue(I18n.shared.lang.tag, forHTTPHeaderField: "Accept-Language")
        if let cookie = cookies.header(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    /// Records cookies and the server clock from any response.
    public func absorb(_ response: URLResponse, for url: URL) {
        guard let http = response as? HTTPURLResponse else { return }
        cookies.store(from: http, url: url)
        if let time = http.value(forHTTPHeaderField: "X-Server-Time"), let ms = Double(time) {
            clock.record(serverEpochMs: ms)
        }
    }

    /// Sends `request` and returns the body of a 2xx answer; anything else becomes an `APIError`.
    public func data(for request: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var request = request
        if let timeout { request.timeoutInterval = timeout }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.offline()
        }
        absorb(response, for: request.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.refusal(status: status, data: data)
        }
        return data
    }

    static func refusal(status: Int, data: Data) -> APIError {
        let object = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        let code = object["code"]?.string ?? "HTTP_\(status)"
        let message = object["message"]?.string ?? t("common.somethingWentWrong")
        var extra = object
        extra["code"] = nil
        extra["message"] = nil
        let error = APIError(status: status, code: code, message: message, extra: extra)
        if status == 401, code == "NO_SESSION" {
            NotificationCenter.default.post(name: .dlSessionEnded, object: nil)
        }
        return error
    }

    func send<Body: Encodable>(_ method: String, _ path: String, query: [String: String] = [:], body: Body) async throws -> Data {
        var request = makeRequest(method, path, query: query)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Coders.encoder().encode(body)
        return try await data(for: request)
    }

    func call<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:]) async throws -> T {
        try decode(await data(for: makeRequest(method, path, query: query)))
    }

    func call<T: Decodable, Body: Encodable>(_ method: String, _ path: String, query: [String: String] = [:], body: Body) async throws -> T {
        try decode(await send(method, path, query: query, body: body))
    }

    func run(_ method: String, _ path: String, query: [String: String] = [:]) async throws {
        _ = try await data(for: makeRequest(method, path, query: query))
    }

    func run<Body: Encodable>(_ method: String, _ path: String, query: [String: String] = [:], body: Body) async throws {
        _ = try await send(method, path, query: query, body: body)
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try Coders.decoder().decode(T.self, from: data)
        } catch {
            throw APIError(status: 0, code: "BAD_RESPONSE", message: t("common.somethingWentWrong"))
        }
    }

    /// Multipart form upload (`kind` + `file`, or just `file`), with progress.
    public func upload<T: Decodable>(
        _ path: String,
        fields: [String: String],
        fileField: String = "file",
        filename: String,
        mime: String,
        data fileData: Data,
        timeout: TimeInterval = 120,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> T {
        let boundary = "dl-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = makeRequest("POST", path)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        let delegate = UploadProgress(progress)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body, delegate: delegate)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw APIError(status: 0, code: "TIMEOUT", message: t("media.uploadTimedOut"))
        } catch {
            throw APIError(status: 0, code: "NETWORK", message: t("media.uploadFailed"))
        }
        absorb(response, for: request.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let refusal = Self.refusal(status: status, data: data)
            throw refusal.code.hasPrefix("HTTP_") && refusal.message == "Something went wrong."
                ? APIError(status: status, code: refusal.code, message: t("media.uploadFailed")) : refusal
        }
        progress?(1)
        return try decode(data)
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let progress: (@Sendable (Double) -> Void)?

    init(_ progress: (@Sendable (Double) -> Void)?) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress?(min(0.99, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
