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
    /// Commands wait here, in the order of their ids, for the one task that writes to the socket:
    /// Home Assistant refuses an id that isn't higher than the previous one.
    private let outbox: AsyncStream<Outgoing>.Continuation
    private let outgoing: AsyncStream<Outgoing>
    private var sendTask: Task<Void, Never>?
    /// Set once the socket is gone, so later commands fail at once instead of waiting forever.
    private var isClosed = false
    private(set) var serverVersion: String?

    private struct Outgoing: Sendable {
        let id: Int
        let message: [String: JSONValue]
    }

    init(transport: any WebSocketTransport, accessToken: String) {
        self.transport = transport
        self.accessToken = accessToken
        (outgoing, outbox) = AsyncStream.makeStream()
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
        sendTask = Task { await self.sendLoop() }
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
        try await withCheckedThrowingContinuation { continuation in
            enqueue(command, replyTo: continuation)
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

    /// Measures the round trip to the server.
    func ping() async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try await send(["type": "ping"])
        return clock.now - start
    }

    func currentUser() async throws -> HomeAssistantUser {
        try await send(["type": "auth/current_user"]).decode(HomeAssistantUser.self)
    }

    func serverConfig() async throws -> ServerConfig {
        try await send(["type": "get_config"]).decode(ServerConfig.self)
    }

    func integrations() async throws -> [Integration] {
        try await send(["type": "config_entries/get"]).decode([Integration].self)
    }

    /// State changes of one entity since `start`, oldest first. The first entry is the state at `start`.
    func history(of entityID: String, since start: Date) async throws -> [StateChange] {
        let result = try await send([
            "type": "history/history_during_period",
            "start_time": .string(start.ISO8601Format()),
            "entity_ids": [.string(entityID)],
            "minimal_response": true,
            "no_attributes": true,
            "significant_changes_only": false,
        ])
        return (result[entityID]?.arrayValue ?? []).compactMap { entry in
            guard let state = entry["s"]?.stringValue, let time = (entry["lc"] ?? entry["lu"])?.doubleValue else { return nil }
            return StateChange(state: state, date: Date(timeIntervalSince1970: time))
        }
    }

    /// Subscribes with the given command and streams the `event` payload of each message.
    func subscribe(_ command: [String: JSONValue]) async throws -> AsyncStream<JSONValue> {
        let (stream, continuation) = AsyncStream<JSONValue>.makeStream()
        var id: Int?
        do {
            _ = try await withCheckedThrowingContinuation { (reply: CheckedContinuation<JSONValue, any Error>) in
                id = enqueue(command, replyTo: reply)
                // Registered before the command leaves, so no event can arrive ahead of it.
                if let id, !isClosed { subscriptions[id] = continuation }
            }
        } catch {
            if let id { subscriptions.removeValue(forKey: id) }
            continuation.finish()
            throw error
        }
        return stream
    }

    // MARK: - Plumbing

    /// Gives the command the next id and queues it in the same step, so ids leave in increasing order.
    @discardableResult
    private func enqueue(_ command: [String: JSONValue], replyTo reply: CheckedContinuation<JSONValue, any Error>) -> Int {
        let id = nextID
        nextID += 1
        guard !isClosed else {
            reply.resume(throwing: HomeAssistantError.connectionClosed)
            return id
        }
        var message = command
        message["id"] = .number(Double(id))
        pending[id] = reply
        outbox.yield(Outgoing(id: id, message: message))
        return id
    }

    /// The only writer to the socket: each command is sent once the previous one has left.
    private func sendLoop() async {
        for await item in outgoing {
            guard !isClosed else {
                pending.removeValue(forKey: item.id)?.resume(throwing: HomeAssistantError.connectionClosed)
                continue
            }
            do {
                try await sendMessage(item.message)
            } catch {
                pending.removeValue(forKey: item.id)?.resume(throwing: error)
            }
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
        case "pong":
            pending.removeValue(forKey: id)?.resume(returning: .null)
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
        isClosed = true
        outbox.finish()
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
        subscriptions.values.forEach { $0.finish() }
        subscriptions.removeAll()
    }
}
