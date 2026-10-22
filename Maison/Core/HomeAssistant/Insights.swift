import Foundation

/// One line of an entity's logbook: what changed, and who or what changed it.
struct LogbookEntry: Sendable, Hashable {
    let date: Date
    let state: String?
    /// The Home Assistant user behind the change, when a person did it.
    let userID: String?
    /// The automation or script behind the change ("Dernier départ").
    let automationName: String?
}

/// One period of long-term statistics (hourly or daily means kept by the recorder).
struct StatisticPoint: Sendable, Hashable {
    let start: Date
    let mean: Double?
    let min: Double?
    let max: Double?
    /// What a total (an energy meter) grew by during the period.
    var change: Double?
}

extension HomeAssistantConnection {
    func logbook(of entityID: String, since start: Date) async throws -> [LogbookEntry] {
        let result = try await send([
            "type": "logbook/get_events",
            "start_time": .string(start.ISO8601Format()),
            "entity_ids": [.string(entityID)],
        ])
        return (result.arrayValue ?? []).compactMap { entry in
            guard let time = entry["when"]?.doubleValue else { return nil }
            let isAutomation = ["automation_triggered", "script_started"].contains(entry["context_event_type"]?.stringValue ?? "")
            return LogbookEntry(
                date: Date(timeIntervalSince1970: time),
                state: entry["state"]?.stringValue,
                userID: entry["context_user_id"]?.stringValue,
                automationName: isAutomation ? entry["context_name"]?.stringValue : nil
            )
        }
    }

    /// Hourly or daily statistics of a sensor that keeps them (`state_class: measurement`).
    func statistics(of entityID: String, since start: Date, period: String) async throws -> [StatisticPoint] {
        let result = try await send([
            "type": "recorder/statistics_during_period",
            "start_time": .string(start.ISO8601Format()),
            "statistic_ids": [.string(entityID)],
            "period": .string(period),
            "types": ["mean", "min", "max", "change"],
        ])
        return (result[entityID]?.arrayValue ?? []).compactMap { point in
            guard let start = point["start"]?.doubleValue else { return nil }
            // Milliseconds since 2023.3, seconds before.
            let seconds = start > 1e11 ? start / 1000 : start
            return StatisticPoint(
                start: Date(timeIntervalSince1970: seconds),
                mean: point["mean"]?.doubleValue,
                min: point["min"]?.doubleValue,
                max: point["max"]?.doubleValue,
                change: point["change"]?.doubleValue
            )
        }
    }

    /// Automations that mention the entity, as entity ids (`automation.trop_chaud`).
    func automations(using entityID: String) async throws -> [String] {
        let result = try await send([
            "type": "search/related",
            "item_type": "entity",
            "item_id": .string(entityID),
        ])
        return (result["automation"]?.arrayValue ?? []).compactMap(\.stringValue)
    }
}

/// Writes automation and script configurations through the REST API used by Home Assistant's own editor
/// (`/api/config/<kind>/config/<id>`). Saving reloads them; it needs an administrator account.
struct ConfigEditor: Sendable {
    let serverURL: URL
    let accessToken: String
    var client: any HTTPClient = URLSessionHTTPClient()

    enum Kind: String, Sendable {
        case automation, script
    }

    func load(_ kind: Kind, id: String) async throws -> JSONValue? {
        let (data, response) = try await client.data(for: request(kind, id: id, method: "GET"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw HomeAssistantError.invalidResponse(statusCode: status) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func save(_ kind: Kind, id: String, config: JSONValue) async throws {
        var request = request(kind, id: id, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(config)
        let (_, response) = try await client.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HomeAssistantError.invalidResponse(statusCode: status) }
    }

    func delete(_ kind: Kind, id: String) async throws {
        let (_, response) = try await client.data(for: request(kind, id: id, method: "DELETE"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) || status == 404 else { throw HomeAssistantError.invalidResponse(statusCode: status) }
    }

    private func request(_ kind: Kind, id: String, method: String) -> URLRequest {
        var request = URLRequest(url: serverURL.appending(path: "api/config/\(kind.rawValue)/config/\(id)"))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
