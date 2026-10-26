import Foundation

/// What a resident asks an administrator for, when their own account can't do it. It reaches the server
/// as a notification; what Maison can do on its own (linking an iPhone to its person) it does on the
/// next administrator's iPhone that opens it.
enum AdministratorRequest: Equatable, Hashable, Sendable {
    case rules
    case turnOffTimer(entityID: String, name: String)
    case openingAlert(entityID: String, name: String)
    case rooms
    /// Count this iPhone at home: add `tracker` to the person of the account `userID`.
    case linkTracker(tracker: String, userID: String)

    static let linkPrefix = "maison_link:"

    /// One notification per request, so that asking twice doesn't add a second one.
    var notificationID: String {
        switch self {
        case .rules: "maison_request_rules"
        case .turnOffTimer(let entityID, _): "maison_request_timer_\(entityID)"
        case .openingAlert(let entityID, _): "maison_request_alert_\(entityID)"
        case .rooms: "maison_request_rooms"
        case .linkTracker(let tracker, let userID): "\(Self.linkPrefix)\(userID):\(tracker)"
        }
    }

    /// The tracker and the account of a link request, from its notification id.
    static func linkRequest(notificationID: String) -> (tracker: String, userID: String)? {
        guard notificationID.hasPrefix(linkPrefix) else { return nil }
        let parts = notificationID.dropFirst(linkPrefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].hasPrefix("device_tracker.") else { return nil }
        return (parts[1], parts[0])
    }

    /// The sentence the administrator reads. `person` is who asks.
    func message(from person: String) -> String {
        switch self {
        case .rules:
            String(localized: "\(person) would like a new rule. Open Maison to create it.")
        case .turnOffTimer(_, let name):
            String(localized: "\(person) would like a turn-off timer on \(name). Open Maison to set it.")
        case .openingAlert(_, let name):
            String(localized: "\(person) would like an alert when \(name) stays open. Open Maison to set it.")
        case .rooms:
            String(localized: "\(person) would like the devices put in their rooms. Open Maison to confirm the rooms it suggests.")
        case .linkTracker:
            String(localized: "\(person)’s iPhone tells the server when they leave or come home. Maison counts them in “When everyone leaves” the next time an administrator opens it.")
        }
    }

    /// The service call that leaves the request on the server, where every account may write it.
    func command(from person: String) -> [String: JSONValue] {
        [
            "type": "call_service",
            "domain": "persistent_notification",
            "service": "create",
            "service_data": [
                "title": "Maison",
                "message": .string(message(from: person)),
                "notification_id": .string(notificationID),
            ],
        ]
    }
}

/// Whether the iPhone's tracker counts for its person, so "When everyone leaves" sees it.
enum TrackerLink: Equatable, Sendable {
    case linked
    /// The tracker or the person isn't on the server yet; trying again later may find them.
    case notYet
    /// Only an administrator can add the tracker to the person.
    case needsAdministrator(AdministratorRequest)
    /// The server refused or didn't answer.
    case failed
}

extension HomeStore {
    /// Leaves the request on the server for an administrator.
    func ask(_ request: AdministratorRequest) async throws {
        guard !isDemoHome else { return }
        guard let connection else { throw HomeAssistantError.connectionClosed }
        _ = try await connection.send(request.command(from: currentUser?.name ?? String(localized: "Someone at home")))
    }

    /// Adds the iPhone's tracker to the person linked to the signed-in user, so they count as home or away.
    /// A resident can't change a person: the result then carries the request for an administrator.
    func attachTracker(webhookID: String) async throws -> TrackerLink {
        guard !isDemoHome else { return .linked }
        guard let connection, let userID = currentUser?.id else { return .notYet }
        let entities = try await connection.send(["type": "config/entity_registry/list"])
        guard let tracker = entities.arrayValue?.first(where: {
            $0["platform"]?.stringValue == "mobile_app" && $0["unique_id"]?.stringValue == webhookID
                && $0["entity_id"]?.stringValue?.hasPrefix("device_tracker.") == true
        })?["entity_id"]?.stringValue else { return .notYet }
        if isResident {
            let person = states.values.first { $0.domain == "person" && $0.attributes["user_id"]?.stringValue == userID }
            let trackers = person?.attributes["device_trackers"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return trackers.contains(tracker) ? .linked : .needsAdministrator(.linkTracker(tracker: tracker, userID: userID))
        }
        return try await Self.link(tracker, toPersonOf: userID, through: connection) ? .linked : .notYet
    }

    /// Adds `tracker` to the person of the account `userID`. `false` when the account has no person.
    static func link(_ tracker: String, toPersonOf userID: String, through connection: HomeAssistantConnection) async throws -> Bool {
        let persons = try await connection.send(["type": "person/list"])
        guard let person = persons["storage"]?.arrayValue?.first(where: { $0["user_id"]?.stringValue == userID }),
              let personID = person["id"]?.stringValue else { return false }
        let trackers = person["device_trackers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        guard !trackers.contains(tracker) else { return true }
        _ = try await connection.send([
            "type": "person/update",
            "person_id": .string(personID),
            "device_trackers": .array((trackers + [tracker]).map { .string($0) }),
        ])
        return true
    }

    /// Does what residents asked for that needs no choice: links their iPhones to their person, then
    /// removes the request. Administrators only. `true` when a person changed.
    @discardableResult
    func linkRequestedTrackers(through connection: HomeAssistantConnection) async -> Bool {
        guard let notifications = try? await connection.send(["type": "persistent_notification/get"]).arrayValue else { return false }
        var changed = false
        for notification in notifications {
            guard let id = notification["notification_id"]?.stringValue,
                  let request = AdministratorRequest.linkRequest(notificationID: id),
                  (try? await Self.link(request.tracker, toPersonOf: request.userID, through: connection)) == true
            else { continue }
            changed = true
            _ = try? await connection.send([
                "type": "call_service",
                "domain": "persistent_notification",
                "service": "dismiss",
                "service_data": ["notification_id": .string(id)],
            ])
        }
        return changed
    }

    /// Removes what Maison registered on the server for this iPhone (its mobile app device and tracker),
    /// on signing out. Only an administrator can; otherwise they stay, unused, and nothing fails.
    static func removeRegistration(webhookID: String, through connection: HomeAssistantConnection, flows: ConfigFlowClient) async -> Bool {
        guard let entries = try? await connection.send(["type": "config/entity_registry/list"]).arrayValue,
              let entryID = entries.first(where: {
                  $0["platform"]?.stringValue == "mobile_app" && $0["unique_id"]?.stringValue?.hasPrefix(webhookID) == true
              })?["config_entry_id"]?.stringValue
        else { return false }
        return (try? await flows.delete(entryID: entryID)) != nil
    }
}
