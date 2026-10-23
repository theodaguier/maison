import Foundation

/// Adds an integration to Home Assistant the way its own settings do, so the person never has to.
/// Needs an administrator's token.
struct ConfigFlowClient: Sendable {
    let serverURL: URL
    let accessToken: String
    var client: any HTTPClient = URLSessionHTTPClient()

    enum Outcome: Equatable, Sendable {
        case created(entryID: String)
        case alreadyConfigured
    }

    /// Starts `handler`'s flow and answers its first form with `answers`.
    func create(_ handler: String, answers: [String: JSONValue]) async throws -> Outcome {
        let started = try await post("api/config/config_entries/flow", body: ["handler": .string(handler), "show_advanced_options": false])
        if let outcome = try outcome(of: started) { return outcome }
        guard let flowID = started["flow_id"]?.stringValue else { throw HomeAssistantError.invalidResponse(statusCode: 200) }
        let answered = try await post("api/config/config_entries/flow/\(flowID)", body: .object(answers))
        guard let outcome = try outcome(of: answered) else { throw HomeAssistantError.invalidResponse(statusCode: 200) }
        return outcome
    }

    /// Confirms a flow Home Assistant started on its own (a device it found on the network) when its
    /// current step asks for nothing but a confirmation. Returns `nil` when the step needs answers.
    func confirmIfNothingToAsk(flowID: String) async throws -> Outcome? {
        let step = try await request("GET", "api/config/config_entries/flow/\(flowID)")
        guard step["type"]?.stringValue == "form", step["data_schema"]?.arrayValue?.isEmpty ?? true else { return nil }
        return try await outcome(of: post("api/config/config_entries/flow/\(flowID)", body: [:]))
    }

    /// Reloads an integration that failed to set up, as its "Reload" menu does.
    func reload(entryID: String) async throws {
        _ = try await request("POST", "api/config/config_entries/entry/\(entryID)/reload")
    }

    /// `nil` while the flow still shows a form.
    private func outcome(of step: JSONValue) throws -> Outcome? {
        switch step["type"]?.stringValue {
        case "create_entry":
            guard let id = step["result"]?["entry_id"]?.stringValue else { throw HomeAssistantError.invalidResponse(statusCode: 200) }
            return .created(entryID: id)
        case "abort" where step["reason"]?.stringValue == "already_configured":
            return .alreadyConfigured
        case "form":
            return nil
        default:
            throw HomeAssistantError.invalidResponse(statusCode: 200)
        }
    }

    private func post(_ path: String, body: JSONValue) async throws -> JSONValue {
        try await request("POST", path, body: body)
    }

    func request(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await client.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HomeAssistantError.invalidResponse(statusCode: status) }
        return data.isEmpty ? .null : try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension HomeAssistantConnection {
    /// Flows Home Assistant started by itself for devices it found, with the integration they're for.
    func discoveredFlows() async throws -> [(flowID: String, handler: String)] {
        let sources: Set = ["zeroconf", "ssdp", "dhcp", "bluetooth", "homekit", "usb", "mqtt", "discovery", "hassio", "integration_discovery"]
        return try await (send(["type": "config_entries/flow/progress"]).arrayValue ?? []).compactMap { flow in
            guard let id = flow["flow_id"]?.stringValue, let handler = flow["handler"]?.stringValue,
                  sources.contains(flow["context"]?["source"]?.stringValue ?? "") else { return nil }
            return (id, handler)
        }
    }

    /// Turns on the `platform` entities an integration ships disabled, picked by their translation key
    /// (`round_trip_time_avg`), which doesn't depend on the server's language. One the person turned
    /// off stays off. Returns how many it turned on and how many were on already: none of either means
    /// the integration hasn't registered them yet.
    func enableEntities(platform: String, translationKeys: Set<String>) async throws -> (turnedOn: Int, alreadyOn: Int) {
        let entries = try await send(["type": "config/entity_registry/list"]).arrayValue ?? []
        var turnedOn = 0, alreadyOn = 0
        for entry in entries where entry["platform"]?.stringValue == platform
            && translationKeys.contains(entry["translation_key"]?.stringValue ?? "") {
            switch entry["disabled_by"]?.stringValue {
            case nil:
                alreadyOn += 1
            case "integration":
                guard let entityID = entry["entity_id"]?.stringValue else { continue }
                _ = try await send(["type": "config/entity_registry/update", "entity_id": .string(entityID), "disabled_by": .null])
                turnedOn += 1
            default:
                continue
            }
        }
        return (turnedOn, alreadyOn)
    }
}

/// What Maison set up on the server by itself, so Settings can say so.
enum ServerSetupLog {
    static let addedKey = "serverSetupAdded"
    static let repairedKey = "serverSetupRepairedAt"

    /// Integration names Maison added, most recent first.
    static var added: [String] { UserDefaults.standard.stringArray(forKey: addedKey) ?? [] }

    static func recordAdded(_ name: String) {
        UserDefaults.standard.set(Array(([name] + added).prefix(20)), forKey: addedKey)
    }

    /// When Maison last reloaded each failing integration, by entry id.
    static var repairedAt: [String: Date] {
        UserDefaults.standard.dictionary(forKey: repairedKey) as? [String: Date] ?? [:]
    }

    static func recordRepair(_ entryID: String, at date: Date) {
        var all = repairedAt
        all[entryID] = date
        UserDefaults.standard.set(all, forKey: repairedKey)
    }
}

/// When Maison switched on the internet check, so the Network fiche can say so.
enum InternetCheckSetting {
    static let addedKey = "internetCheckAddedAt"
    static let attemptedKey = "internetCheckAttemptedAt"
    /// A public address that answers pings everywhere.
    static let host = "1.1.1.1"

    static var addedAt: Date? { UserDefaults.standard.object(forKey: addedKey) as? Date }
}
