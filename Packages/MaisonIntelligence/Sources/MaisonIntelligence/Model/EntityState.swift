import Foundation

/// The current state of one Home Assistant entity, as returned by `get_states` and `subscribe_entities`.
public struct EntityState: Sendable, Hashable, Identifiable, Decodable {
    public let entityID: String
    public let state: String
    public let attributes: [String: JSONValue]
    public var lastChanged: Date?

    public var id: String { entityID }

    public var domain: String {
        String(entityID.prefix { $0 != "." })
    }

    public var kind: DeviceKind {
        DeviceKind(entityID: entityID)
    }

    public var name: String {
        attributes["friendly_name"]?.stringValue ?? entityID
    }

    public var isUnavailable: Bool {
        state == "unavailable" || state == "unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
    }

    public init(entityID: String, state: String, attributes: [String: JSONValue] = [:], lastChanged: Date? = nil) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(String.self, forKey: .entityID)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .attributes) ?? [:]
        lastChanged = try container.decodeIfPresent(String.self, forKey: .lastChanged).flatMap(Self.parseDate)
    }

    /// Home Assistant timestamps carry microseconds (`2026-10-20T08:12:03.123456+00:00`),
    /// which ISO8601DateFormatter cannot read, so the fraction is trimmed to milliseconds.
    public static func parseDate(_ string: String) -> Date? {
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

/// The values an entity's attributes carry, read without wording them: the app turns them into text.
public extension EntityState {
    var deviceClass: String? { attributes["device_class"]?.stringValue }
    var unit: String? { attributes["unit_of_measurement"]?.stringValue }
    var numericState: Double? { Double(state) }

    /// Whether the device is in its active state (on, open, unlocked, playing…).
    var isActive: Bool {
        ["on", "open", "opening", "unlocked", "playing", "cleaning", "heat", "cool", "heat_cool", "auto"].contains(state)
    }

    /// Light brightness or cover position, 0…1, when the device exposes one.
    var level: Double? {
        switch kind {
        case .light:
            guard state == "on" else { return 0 }
            return attributes["brightness"]?.doubleValue.map { $0 / 255 } ?? 1
        case .cover:
            return attributes["current_position"]?.doubleValue.map { $0 / 100 }
        case .fan:
            guard state == "on" else { return 0 }
            return attributes["percentage"]?.doubleValue.map { $0 / 100 }
        default:
            return nil
        }
    }

    var supportsLevel: Bool {
        switch kind {
        case .light:
            let modes = attributes["supported_color_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return attributes["brightness"] != nil || modes.contains { $0 != "onoff" }
        case .cover:
            return attributes["current_position"] != nil
        case .fan:
            return attributes["percentage"] != nil
        default:
            return false
        }
    }

    var targetTemperature: Double? { attributes["temperature"]?.doubleValue }
    var currentTemperature: Double? { attributes["current_temperature"]?.doubleValue }
    var temperatureStep: Double { attributes["target_temp_step"]?.doubleValue ?? 0.5 }
    var hvacAction: String? { attributes["hvac_action"]?.stringValue }
}
