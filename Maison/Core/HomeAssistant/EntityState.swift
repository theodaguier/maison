import Foundation

/// The current state of one Home Assistant entity, as returned by `get_states` and `state_changed` events.
struct EntityState: Sendable, Hashable, Identifiable, Decodable {
    let entityID: String
    let state: String
    let attributes: [String: JSONValue]
    var lastChanged: Date?

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
        case lastChanged = "last_changed"
    }

    init(entityID: String, state: String, attributes: [String: JSONValue] = [:], lastChanged: Date? = nil) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(String.self, forKey: .entityID)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .attributes) ?? [:]
        lastChanged = try container.decodeIfPresent(String.self, forKey: .lastChanged).flatMap(Self.parseDate)
    }

    /// Home Assistant timestamps carry microseconds (`2026-10-20T08:12:03.123456+00:00`),
    /// which ISO8601DateFormatter cannot read, so the fraction is trimmed to milliseconds.
    static func parseDate(_ string: String) -> Date? {
        var value = string
        if let dot = value.firstIndex(of: "."),
           let zone = value[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = value[value.index(after: dot)..<zone].prefix(3)
            value = String(value[..<dot]) + "." + fraction + String(value[zone...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
