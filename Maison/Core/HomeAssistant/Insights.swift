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
    /// The running total at the end of the period.
    var sum: Double?
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
            "types": ["mean", "min", "max", "change", "sum"],
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
                change: point["change"]?.doubleValue,
                sum: point["sum"]?.doubleValue
            )
        }
    }

    /// The statistics Home Assistant's Energy dashboard counts as electricity taken from the grid.
    func gridConsumptionStatistics() async throws -> [String] {
        let prefs = try await send(["type": "energy/get_prefs"])
        return (prefs["energy_sources"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "grid" }
            .flatMap { $0["flow_from"]?.arrayValue ?? [] }
            .compactMap { $0["stat_energy_from"]?.stringValue }
    }

    /// Makes the statistic the grid meter of Home Assistant's Energy dashboard, the same way its own
    /// settings do, keeping every other source. Needs an administrator account.
    func setGridMeter(_ statisticID: String) async throws {
        // A server whose dashboard was never set up has no preferences yet.
        let sources = (try? await send(["type": "energy/get_prefs"]))?["energy_sources"]?.arrayValue ?? []
        _ = try await send([
            "type": "energy/save_prefs",
            "energy_sources": .array(EnergyPrefs.settingGridMeter(statisticID, in: sources)),
        ])
    }

    /// The price set for grid electricity in the Energy dashboard: a fixed number, or an entity whose
    /// state is the price (a tariff that changes).
    func gridEnergyPrice() async throws -> (fixed: Double?, entityID: String?) {
        let prefs = try await send(["type": "energy/get_prefs"])
        let flows = (prefs["energy_sources"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "grid" }
            .flatMap { $0["flow_from"]?.arrayValue ?? [] }
        for flow in flows {
            if let fixed = flow["number_energy_price"]?.doubleValue { return (fixed, nil) }
            if let entity = flow["entity_energy_price"]?.stringValue { return (nil, entity) }
        }
        return (nil, nil)
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

/// Home Assistant's Energy dashboard preferences.
enum EnergyPrefs {
    /// `sources` with `statisticID` as what the grid delivers: added to the grid source, or a grid source
    /// made for it. Solar, gas, water and the price already set stay as they are.
    static func settingGridMeter(_ statisticID: String, in sources: [JSONValue]) -> [JSONValue] {
        let flow: JSONValue = .object([
            "stat_energy_from": .string(statisticID),
            "stat_cost": .null,
            "entity_energy_price": .null,
            "number_energy_price": .null,
        ])
        guard let index = sources.firstIndex(where: { $0["type"]?.stringValue == "grid" }),
              case .object(var grid) = sources[index] else {
            return sources + [.object([
                "type": "grid",
                "flow_from": .array([flow]),
                "flow_to": .array([]),
                "cost_adjustment_day": .number(0),
            ])]
        }
        let flows = grid["flow_from"]?.arrayValue ?? []
        guard !flows.contains(where: { $0["stat_energy_from"]?.stringValue == statisticID }) else { return sources }
        grid["flow_from"] = .array(flows + [flow])
        var result = sources
        result[index] = .object(grid)
        return result
    }
}
