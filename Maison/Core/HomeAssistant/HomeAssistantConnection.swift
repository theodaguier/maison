import Foundation

/// A text WebSocket. Abstracted so the connection can be tested without a server.
protocol WebSocketTransport: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

final class URLSessionWebSocketTransport: WebSocketTransport {
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// Client for the Home Assistant WebSocket API (`/api/websocket`).
///
/// Call `connect()` once, then send commands. Replies are matched to commands by id, and
/// subscription events are delivered through `AsyncStream`s.
actor HomeAssistantConnection {
    private let transport: any WebSocketTransport
    private let accessToken: String

    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var subscriptions: [Int: AsyncStream<JSONValue>.Continuation] = [:]
    private var receiveTask: Task<Void, Never>?
    private(set) var serverVersion: String?

    init(transport: any WebSocketTransport, accessToken: String) {
        self.transport = transport
        self.accessToken = accessToken
    }

    init(serverURL: URL, accessToken: String) {
        self.init(
            transport: URLSessionWebSocketTransport(url: Self.webSocketURL(for: serverURL)),
            accessToken: accessToken
        )
    }

    static func webSocketURL(for serverURL: URL) -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        components.query = nil
        return components.url!
    }

    // MARK: - Lifecycle

    func connect() async throws {
        let greeting = try await receiveMessage()
        guard greeting["type"]?.stringValue == "auth_required" else {
            throw HomeAssistantError.authenticationFailed("Unexpected greeting")
        }
        try await sendMessage(["type": "auth", "access_token": .string(accessToken)])

        let reply = try await receiveMessage()
        switch reply["type"]?.stringValue {
        case "auth_ok":
            serverVersion = reply["ha_version"]?.stringValue
        case "auth_invalid":
            throw HomeAssistantError.authenticationFailed(reply["message"]?.stringValue)
        default:
            throw HomeAssistantError.authenticationFailed("Unexpected reply")
        }

        receiveTask = Task { await self.receiveLoop() }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        transport.close()
        failAll(with: HomeAssistantError.connectionClosed)
    }

    // MARK: - Commands

    /// Sends a command and returns its `result` payload.
    @discardableResult
    func send(_ command: [String: JSONValue]) async throws -> JSONValue {
        let id = makeID()
        var message = command
        message["id"] = .number(Double(id))
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { await self.deliver(message, id: id) }
        }
    }

    func states() async throws -> [EntityState] {
        try await send(["type": "get_states"]).decode([EntityState].self)
    }

    func callService(domain: String, service: String, entityID: String, data: [String: JSONValue] = [:]) async throws {
        var command: [String: JSONValue] = [
            "type": "call_service",
            "domain": .string(domain),
            "service": .string(service),
            "target": ["entity_id": .string(entityID)],
        ]
        if !data.isEmpty {
            command["service_data"] = .object(data)
        }
        try await send(command)
    }

    /// Streams the new state of every entity that changes. Removed entities are skipped.
    func stateChanges() async throws -> AsyncStream<EntityState> {
        let events = try await subscribe(["type": "subscribe_events", "event_type": "state_changed"])
        return AsyncStream { continuation in
            let task = Task {
                for await event in events {
                    guard
                        let newState = event["data"]?["new_state"], !newState.isNull,
                        let state = try? newState.decode(EntityState.self)
                    else { continue }
                    continuation.yield(state)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Subscribes with the given command and streams the `event` payload of each message.
    func subscribe(_ command: [String: JSONValue]) async throws -> AsyncStream<JSONValue> {
        let id = makeID()
        let (stream, continuation) = AsyncStream<JSONValue>.makeStream()
        subscriptions[id] = continuation

        var message = command
        message["id"] = .number(Double(id))
        do {
            _ = try await withCheckedThrowingContinuation { (reply: CheckedContinuation<JSONValue, any Error>) in
                pending[id] = reply
                Task { await self.deliver(message, id: id) }
            }
        } catch {
            subscriptions.removeValue(forKey: id)?.finish()
            throw error
        }
        return stream
    }

    // MARK: - Plumbing

    private func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func deliver(_ message: [String: JSONValue], id: Int) async {
        do {
            try await sendMessage(message)
        } catch {
            pending.removeValue(forKey: id)?.resume(throwing: error)
        }
    }

    private func sendMessage(_ message: [String: JSONValue]) async throws {
        let data = try JSONEncoder().encode(JSONValue.object(message))
        try await transport.send(String(decoding: data, as: UTF8.self))
    }

    private func receiveMessage() async throws -> JSONValue {
        let text = try await transport.receive()
        return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                handle(try await receiveMessage())
            } catch {
                failAll(with: HomeAssistantError.connectionClosed)
                return
            }
        }
    }

    private func handle(_ message: JSONValue) {
        guard let id = message["id"]?.intValue else { return }
        switch message["type"]?.stringValue {
        case "result":
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if message["success"]?.boolValue == true {
                continuation.resume(returning: message["result"] ?? .null)
            } else {
                let error = message["error"]
                continuation.resume(throwing: HomeAssistantError.commandFailed(
                    code: error?["code"]?.stringValue ?? "unknown",
                    message: error?["message"]?.stringValue ?? ""
                ))
                subscriptions.removeValue(forKey: id)?.finish()
            }
        case "event":
            if let event = message["event"] {
                subscriptions[id]?.yield(event)
            }
        default:
            break
        }
    }

    private func failAll(with error: any Error) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
        subscriptions.values.forEach { $0.finish() }
        subscriptions.removeAll()
    }
}
