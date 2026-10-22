import Foundation
@testable import Maison

/// A connection whose replies are the JSON files under `Fixtures/HomeAssistant`.
func recordedConnection(results: [String: String] = [:], events: [String: String] = [:]) async throws -> HomeAssistantConnection {
    let directory = "Fixtures/HomeAssistant"
    let greeting = try RecordedFixture.json("auth-required", directory: directory)
    let authOK = try RecordedFixture.json("auth-ok", directory: directory)
    let payloads = try loadFixtures(results, directory: directory)
    let eventPayloads = try loadFixtures(events, directory: directory).mapValues { value in
        value.arrayValue ?? [value]
    }
    let transport = FakeTransport(responder: { message in
        switch message["type"]?.stringValue {
        case "auth":
            return [authOK]
        case let type? where payloads[type] != nil:
            return [result(for: message, payloads[type]!)]
        case let type? where eventPayloads[type] != nil:
            return [result(for: message)] + eventPayloads[type]!.map { event in
                ["id": message["id"] ?? .null, "type": "event", "event": event]
            }
        default:
            return []
        }
    }, greeting: greeting)
    let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
    try await connection.connect()
    return connection
}

private func loadFixtures(_ names: [String: String], directory: String) throws -> [String: JSONValue] {
    var payloads: [String: JSONValue] = [:]
    for (type, name) in names {
        payloads[type] = try RecordedFixture.json(name, directory: directory)
    }
    return payloads
}
