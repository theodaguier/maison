import Foundation

/// The current state of one Home Assistant entity, as returned by `get_states` and `state_changed` events.
struct EntityState: Sendable, Hashable, Identifiable, Decodable {
    let entityID: String
    let state: String
    let attributes: [String: JSONValue]

    var id: String { entityID }

    var domain: String {
        String(entityID.prefix { $0 != "." })
    }

    var kind: DeviceKind {
        DeviceKind(entityID: entityID)
    }

    var name: String {
        attributes["friendly_name"]?.stringValue ?? entityID
    }

    var isUnavailable: Bool {
        state == "unavailable" || state == "unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
    }

    init(entityID: String, state: String, attributes: [String: JSONValue] = [:]) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(String.self, forKey: .entityID)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .attributes) ?? [:]
    }
}
