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
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await client.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HomeAssistantError.invalidResponse(statusCode: status) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension HomeAssistantConnection {
    /// Turns on the entities an integration ships disabled, picked by their translation key
    /// (`round_trip_time_avg`), which doesn't depend on the server's language.
    func enableEntities(ofEntry entryID: String, translationKeys: Set<String>) async throws {
        let entries = try await send(["type": "config/entity_registry/list"]).arrayValue ?? []
        for entry in entries where entry["config_entry_id"]?.stringValue == entryID
            && entry["disabled_by"]?.stringValue == "integration"
            && translationKeys.contains(entry["translation_key"]?.stringValue ?? "") {
            guard let entityID = entry["entity_id"]?.stringValue else { continue }
            _ = try await send(["type": "config/entity_registry/update", "entity_id": .string(entityID), "disabled_by": .null])
        }
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
