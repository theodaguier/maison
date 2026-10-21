import Foundation
@testable import Maison
import Testing

struct HomeAssistantConnectionTests {
    @Test func authenticatesWithTheAccessToken() async throws {
        let transport = FakeTransport()
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token-123")

        try await connection.connect()

        let auth = try #require(await transport.sentMessages(ofType: "auth").first)
        #expect(auth["access_token"] == "token-123")
        #expect(await connection.serverVersion == "2026.8.1")
    }

    @Test func rejectsAnInvalidToken() async throws {
        let transport = FakeTransport { message in
            message["type"]?.stringValue == "auth" ? [["type": "auth_invalid", "message": "Invalid access token"]] : []
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "expired")

        await #expect(throws: HomeAssistantError.authenticationFailed("Invalid access token")) {
            try await connection.connect()
        }
    }

    @Test func fetchesStates() async throws {
        let transport = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": [["type": "auth_ok"]]
            case "get_states": [result(for: message, [
                    ["entity_id": "light.living_room", "state": "on", "attributes": ["friendly_name": "Living Room", "brightness": 180]],
                    ["entity_id": "sensor.bedroom_temperature", "state": "21.5", "attributes": ["unit_of_measurement": "°C"]],
                ])]
            default: []
            }
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        let states = try await connection.states()

        #expect(states.map(\.entityID) == ["light.living_room", "sensor.bedroom_temperature"])
        #expect(states[0].name == "Living Room")
        #expect(states[0].attributes["brightness"]?.intValue == 180)
        #expect(states[1].kind == .sensor)
        #expect(states[1].name == "sensor.bedroom_temperature")
    }

    @Test func givesEveryCommandItsOwnID() async throws {
        let transport = FakeTransport { message in
            message["type"]?.stringValue == "auth" ? [["type": "auth_ok"]] : [result(for: message)]
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        try await connection.send(["type": "ping"])
        try await connection.send(["type": "ping"])

        let ids = await transport.sentMessages(ofType: "ping").compactMap { $0["id"]?.intValue }
        #expect(ids == [1, 2])
    }

    @Test func callsAService() async throws {
        let transport = FakeTransport { message in
            message["type"]?.stringValue == "auth" ? [["type": "auth_ok"]] : [result(for: message)]
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        try await connection.callService(domain: "light", service: "turn_on", entityID: "light.desk", data: ["brightness_pct": 40])

        let call = try #require(await transport.sentMessages(ofType: "call_service").first)
        #expect(call["domain"] == "light")
        #expect(call["service"] == "turn_on")
        #expect(call["target"]?["entity_id"] == "light.desk")
        #expect(call["service_data"]?["brightness_pct"] == 40)
    }

    @Test func surfacesCommandErrors() async throws {
        let transport = FakeTransport { message in
            guard message["type"]?.stringValue != "auth" else { return [["type": "auth_ok"]] }
            return [[
                "id": message["id"] ?? .null, "type": "result", "success": false,
                "error": ["code": "not_found", "message": "Service not found."],
            ]]
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        await #expect(throws: HomeAssistantError.commandFailed(code: "not_found", message: "Service not found.")) {
            try await connection.callService(domain: "light", service: "explode", entityID: "light.desk")
        }
    }

    @Test func streamsStateChanges() async throws {
        let transport = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": [["type": "auth_ok"]]
            case "subscribe_events": [
                    result(for: message),
                    ["id": message["id"] ?? .null, "type": "event", "event": [
                        "event_type": "state_changed",
                        "data": ["entity_id": "light.gone", "new_state": nil],
                    ]],
                    ["id": message["id"] ?? .null, "type": "event", "event": [
                        "event_type": "state_changed",
                        "data": ["entity_id": "light.desk", "new_state": ["entity_id": "light.desk", "state": "off", "attributes": [:]]],
                    ]],
                ]
            default: []
            }
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        let changes = try await connection.stateChanges()
        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()

        #expect(first == EntityState(entityID: "light.desk", state: "off"))
        let subscription = try #require(await transport.sentMessages(ofType: "subscribe_events").first)
        #expect(subscription["event_type"] == "state_changed")
    }

    @Test func failsPendingCommandsWhenDisconnected() async throws {
        let transport = FakeTransport()
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        let reply = Task { try await connection.send(["type": "never_answered"]) }
        while await transport.sentMessages(ofType: "never_answered").isEmpty {
            await Task.yield()
        }
        await connection.disconnect()

        await #expect(throws: HomeAssistantError.connectionClosed) {
            try await reply.value
        }
    }

    @Test(arguments: [
        ("http://192.168.1.179:8123", "ws://192.168.1.179:8123/api/websocket"),
        ("https://home.example.com", "wss://home.example.com/api/websocket"),
        ("https://home.example.com/lovelace?x=1", "wss://home.example.com/api/websocket"),
    ])
    func webSocketURL(server: String, expected: String) {
        #expect(HomeAssistantConnection.webSocketURL(for: URL(string: server)!).absoluteString == expected)
    }
}
