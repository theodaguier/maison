import Foundation
@testable import Maison

/// In-memory WebSocket: replies are produced by `responder` for every message the client sends.
actor FakeTransport: WebSocketTransport {
    private var inbox: [String] = []
    private var waiters: [CheckedContinuation<String, any Error>] = []
    private let responder: @Sendable (JSONValue) -> [JSONValue]
    private(set) var sent: [JSONValue] = []

    /// Starts with Home Assistant's `auth_required` greeting already queued.
    init(responder: @escaping @Sendable (JSONValue) -> [JSONValue] = FakeTransport.acceptingAuth) {
        self.responder = responder
        inbox = [Self.encode(["type": "auth_required", "ha_version": "2026.8.1"])]
    }

    func send(_ text: String) async throws {
        let message = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        sent.append(message)
        responder(message).forEach { push($0) }
    }

    func receive() async throws -> String {
        if !inbox.isEmpty {
            return inbox.removeFirst()
        }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    nonisolated func close() {}

    func push(_ message: JSONValue) {
        let text = Self.encode(message)
        if waiters.isEmpty {
            inbox.append(text)
        } else {
            waiters.removeFirst().resume(returning: text)
        }
    }

    func sentMessages(ofType type: String) -> [JSONValue] {
        sent.filter { $0["type"]?.stringValue == type }
    }

    static let acceptingAuth: @Sendable (JSONValue) -> [JSONValue] = { message in
        message["type"]?.stringValue == "auth" ? [["type": "auth_ok", "ha_version": "2026.8.1"]] : []
    }

    private static func encode(_ message: JSONValue) -> String {
        String(decoding: try! JSONEncoder().encode(message), as: UTF8.self)
    }
}

/// Builds a successful `result` reply for the command it answers.
func result(for command: JSONValue, _ payload: JSONValue = .null) -> JSONValue {
    ["id": command["id"] ?? .null, "type": "result", "success": true, "result": payload]
}

struct StubHTTPClient: HTTPClient {
    let statusCode: Int
    let body: String
    let onRequest: @Sendable (URLRequest) -> Void

    init(statusCode: Int = 200, body: String, onRequest: @escaping @Sendable (URLRequest) -> Void = { _ in }) {
        self.statusCode = statusCode
        self.body = body
        self.onRequest = onRequest
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        onRequest(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

/// Thread-safe box for capturing values from `@Sendable` closures in tests.
final class Captured<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }
}

/// The keychain's stand-in: unsigned test builds can't use the keychain.
final class MemoryCredentialStorage: CredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?

    func load() throws -> Credentials? { lock.withLock { credentials } }
    func save(_ credentials: Credentials) throws { lock.withLock { self.credentials = credentials } }
    func delete() throws { lock.withLock { credentials = nil } }
}
