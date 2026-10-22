import Foundation
@testable import Maison
import Testing

/// Answers each request with the reply for its path, and keeps what was sent.
private final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private let reply: @Sendable (URLRequest) -> (status: Int, body: String)
    private var requests: [URLRequest] = []

    init(_ reply: @escaping @Sendable (URLRequest) -> (status: Int, body: String)) {
        self.reply = reply
    }

    var sent: [URLRequest] { lock.withLock { requests } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { requests.append(request) }
        let (status, body) = reply(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

struct ConfigFlowTests {
    private let server = URL(string: "http://homeassistant.local:8123")!

    @Test func addsPingWithoutAskingAnything() async throws {
        let http = ScriptedHTTPClient { request in
            if request.url?.path() == "/api/config/config_entries/flow" {
                return (200, #"{"type": "form", "flow_id": "f1", "step_id": "user", "data_schema": []}"#)
            }
            return (200, #"{"type": "create_entry", "result": {"entry_id": "entry-ping"}}"#)
        }

        let outcome = try await ConfigFlowClient(serverURL: server, accessToken: "token", client: http)
            .create("ping", answers: ["host": "1.1.1.1"])

        #expect(outcome == .created(entryID: "entry-ping"))
        #expect(http.sent.map { $0.url?.path() } == ["/api/config/config_entries/flow", "/api/config/config_entries/flow/f1"])
        let bodies = http.sent.map { String(decoding: $0.httpBody ?? Data(), as: UTF8.self) }
        #expect(bodies[0].contains(#""handler":"ping""#))
        #expect(bodies[1].contains(#""host":"1.1.1.1""#))
        #expect(http.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token" })
    }

    @Test func anIntegrationAlreadyThereIsNotAnError() async throws {
        let http = ScriptedHTTPClient { _ in (200, #"{"type": "abort", "reason": "already_configured"}"#) }

        let outcome = try await ConfigFlowClient(serverURL: server, accessToken: "token", client: http)
            .create("ping", answers: ["host": "1.1.1.1"])
        #expect(outcome == .alreadyConfigured)
    }

    @Test func aRefusedFlowThrows() async throws {
        let http = ScriptedHTTPClient { _ in (401, "") }

        await #expect(throws: HomeAssistantError.self) {
            _ = try await ConfigFlowClient(serverURL: server, accessToken: "token", client: http)
                .create("ping", answers: ["host": "1.1.1.1"])
        }
    }

    @Test func turnsOnOnlyTheAverageResponseTime() async throws {
        let registry: JSONValue = [
            ["entity_id": "binary_sensor.1_1_1_1", "config_entry_id": "entry-ping", "disabled_by": .null, "translation_key": .null],
            ["entity_id": "sensor.1_1_1_1_round_trip_time_average", "config_entry_id": "entry-ping", "disabled_by": "integration", "translation_key": "round_trip_time_avg"],
            ["entity_id": "sensor.1_1_1_1_round_trip_time_maximum", "config_entry_id": "entry-ping", "disabled_by": "integration", "translation_key": "round_trip_time_max"],
            ["entity_id": "sensor.other_average", "config_entry_id": "other", "disabled_by": "integration", "translation_key": "round_trip_time_avg"],
        ]
        let transport = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": [["type": "auth_ok", "ha_version": "2026.8.1"]]
            case "config/entity_registry/list": [result(for: message, registry)]
            default: [result(for: message)]
            }
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        try await connection.enableEntities(ofEntry: "entry-ping", translationKeys: ["round_trip_time_avg"])

        let updates = await transport.sentMessages(ofType: "config/entity_registry/update")
        #expect(updates.map { $0["entity_id"]?.stringValue } == ["sensor.1_1_1_1_round_trip_time_average"])
        #expect(updates.first?["disabled_by"] == .null)
    }
}
