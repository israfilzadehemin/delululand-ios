@testable import DLData
import DLNetwork
import Foundation
import Testing

@Suite("Push links")
struct PushLinkTests {
    @Test("A push's url opens its screen; anything else opens Home")
    func links() {
        #expect(AppLink(path: "/letters/8c1f0a52") == .letter("8c1f0a52"))
        #expect(AppLink(path: "/letters") == .letters)
        #expect(AppLink(path: "/discussions/d-1") == .discussion("d-1"))
        #expect(AppLink(path: "/discussions/") == .discussions)
        #expect(AppLink(path: "/emails/thread-9") == .thread("thread-9"))
        #expect(AppLink(path: "/emails") == .emails)
        #expect(AppLink(path: "/letters/abc?x=1") == .letter("abc"))
        #expect(AppLink(path: "/home") == .home)
        #expect(AppLink(path: "/") == .home)
        #expect(AppLink(path: nil) == .home)
        #expect(AppLink(path: "/board") == .home)
    }

    @Test("The APNs token is sent as lower-case hex")
    func hex() {
        #expect(PushStore.hex(Data([0x00, 0x0f, 0xa1, 0xff])) == "000fa1ff")
    }

    @Test("Debug builds say sandbox, everything else production")
    func environment() {
        #expect(AppConfig(info: ["DLApnsEnvironment": "sandbox"]).apnsEnvironment == "sandbox")
        #expect(AppConfig(info: ["DLApnsEnvironment": "production"]).apnsEnvironment == "production")
        #expect(AppConfig(info: [:]).apnsEnvironment == "production")
        #expect(AppConfig(info: ["DLApnsEnvironment": "$(DL_APNS_ENVIRONMENT)"]).apnsEnvironment == "production")
    }

    @Test("The shared keychain group comes from the Info.plist; unset or unexpanded means none (Read Ticks TK2)")
    func keychainGroup() {
        #expect(AppConfig(info: ["DLKeychainGroup": "NM3GZ4M68M.com.delulutopia.shared"]).keychainGroup == "NM3GZ4M68M.com.delulutopia.shared")
        #expect(AppConfig(info: [:]).keychainGroup == nil)
        #expect(AppConfig(info: ["DLKeychainGroup": "$(DL_KEYCHAIN_GROUP)"]).keychainGroup == nil)
        #expect(AppConfig.cookieService(.prod) == "com.delulutopia.cookies.prod")
    }

    @Test("Without the group's entitlement (simulator tests) the jar stays usable in the app's own group")
    func jarWithoutEntitlement() {
        let jar = CookieStore(service: "com.delulutopia.cookies.test-\(UUID().uuidString)", accessGroup: "NM3GZ4M68M.com.delulutopia.shared")
        #expect(jar.names.isEmpty)
        jar.clear()
    }
}

/// Answers every request 204 and keeps what was sent.
final class PushRecorder: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [(method: String, path: String, body: [String: Any])] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        Self.lock.withLock { Self.requests.append((request.httpMethod ?? "", request.url?.path ?? "", body)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Push registration", .serialized)
struct PushRegistrationTests {
    private func store() -> PushStore {
        PushRecorder.lock.withLock { PushRecorder.requests = [] }
        let client = APIClient(
            baseURL: URL(string: "https://test.delulutopia.com")!,
            cookies: CookieStore(service: "dl.push.test.\(UUID().uuidString)", inMemory: true),
            userAgent: "test",
            protocolClasses: [PushRecorder.self]
        )
        return PushStore(api: API(client: client), topic: "com.delulutopia.app.test", environment: "sandbox", system: false) {}
    }

    private func sent() async -> [(method: String, path: String, body: [String: Any])] {
        for _ in 0..<50 {
            let r = PushRecorder.lock.withLock { PushRecorder.requests }
            if !r.isEmpty { return r }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return []
    }

    @Test("The token waits for sign-in, then goes once with the topic and environment; log-out removes it")
    func register() async throws {
        let push = store()
        push.didRegister(tokenData: Data([0xab, 0xcd]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await sent().isEmpty == true || PushRecorder.requests.isEmpty)

        push.didSignIn()
        push.didRegister(tokenData: Data([0xab, 0xcd]))
        let first = await sent()
        let put = try #require(first.first)
        #expect(put.method == "PUT")
        #expect(put.path == "/api/push/devices")
        #expect(put.body["platform"] as? String == "apns")
        #expect(put.body["token"] as? String == "abcd")
        #expect(put.body["appId"] as? String == "com.delulutopia.app.test")
        #expect(put.body["environment"] as? String == "sandbox")

        // The same token again (every start): not sent twice in a session.
        push.didRegister(tokenData: Data([0xab, 0xcd]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(PushRecorder.lock.withLock { PushRecorder.requests.count } == 1)

        await push.willSignOut()
        let all = PushRecorder.lock.withLock { PushRecorder.requests }
        let delete = try #require(all.last)
        #expect(delete.method == "DELETE")
        #expect(delete.body["token"] as? String == "abcd")
        #expect(delete.body["platform"] as? String == "apns")
    }

    @Test("A tapped notification becomes the pending link")
    func open() {
        let push = store()
        push.open(path: "/emails/t-1")
        #expect(push.pendingLink == .thread("t-1"))
    }
}
