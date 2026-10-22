import Foundation

/// A Home Assistant area, shown as a room.
struct Area: Sendable, Hashable, Identifiable, Decodable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey {
        case id = "area_id"
        case name
    }
}

/// The parts of the entity registry the app needs: where an entity lives and whether to show it.
struct EntityRegistryEntry: Sendable, Hashable, Decodable {
    let entityID: String
    let areaID: String?
    let deviceID: String?
    let hiddenBy: String?
    let disabledBy: String?
    let entityCategory: String?
    /// The integration that provides the entity ("sonos", "hue").
    var platform: String?

    var isVisible: Bool {
        hiddenBy == nil && disabledBy == nil && entityCategory == nil
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case areaID = "area_id"
        case deviceID = "device_id"
        case hiddenBy = "hidden_by"
        case disabledBy = "disabled_by"
        case entityCategory = "entity_category"
        case platform
    }
}

struct DeviceRegistryEntry: Sendable, Hashable, Decodable {
    let id: String
    let areaID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case areaID = "area_id"
    }
}

/// Everything the registries say about how entities are organised.
struct HomeLayout: Sendable, Hashable {
    var areas: [Area] = []
    var areaByEntity: [String: String] = [:]
    var deviceByEntity: [String: String] = [:]
    var hiddenEntities: Set<String> = []
    var platformByEntity: [String: String] = [:]

    init() {}

    init(areas: [Area], entities: [EntityRegistryEntry], devices: [DeviceRegistryEntry]) {
        self.areas = areas.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let deviceAreas = Dictionary(devices.map { ($0.id, $0.areaID) }, uniquingKeysWith: { first, _ in first })
        for entry in entities {
            if let area = entry.areaID ?? entry.deviceID.flatMap({ deviceAreas[$0] ?? nil }) {
                areaByEntity[entry.entityID] = area
            }
            if let device = entry.deviceID {
                deviceByEntity[entry.entityID] = device
            }
            if let platform = entry.platform {
                platformByEntity[entry.entityID] = platform
            }
            if !entry.isVisible {
                hiddenEntities.insert(entry.entityID)
            }
        }
    }
}

struct HomeAssistantUser: Sendable, Hashable, Decodable {
    var id: String?
    let name: String
    let isAdmin: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isAdmin = "is_admin"
    }
}

struct ServerConfig: Sendable, Hashable, Decodable {
    let locationName: String?
    let version: String?
    let externalURL: String?
    let internalURL: String?
    /// ISO 3166 code set in Home Assistant's general settings ("FR").
    var country: String?

    private enum CodingKeys: String, CodingKey {
        case locationName = "location_name"
        case version
        case externalURL = "external_url"
        case internalURL = "internal_url"
        case country
    }
}

struct StateChange: Sendable, Hashable {
    let state: String
    let date: Date
}

/// When a device was on during one day.
struct DayUsage: Sendable, Equatable {
    /// On periods, clipped to the day.
    let periods: [DateInterval]
    let day: DateInterval

    var total: TimeInterval { periods.reduce(0) { $0 + $1.duration } }

    /// Builds the on periods within `day` from a history whose first entry is the state at its start.
    init(changes: [StateChange], day: DateInterval, now: Date = .now, isOn: (String) -> Bool = { $0 == "on" }) {
        self.day = day
        let end = min(day.end, now)
        var periods: [DateInterval] = []
        var onSince: Date?
        for change in changes.sorted(by: { $0.date < $1.date }) {
            // Changes after the day (yesterday's usage is read from a history that runs to now) are clamped to its end.
            let date = min(max(change.date, day.start), end)
            if isOn(change.state) {
                if onSince == nil { onSince = date }
            } else if let start = onSince {
                if date > start { periods.append(DateInterval(start: start, end: date)) }
                onSince = nil
            }
        }
        if let start = onSince, end > start {
            periods.append(DateInterval(start: start, end: end))
        }
        self.periods = periods.filter { $0.end > day.start && $0.start < end }
    }

    init(periods: [DateInterval], day: DateInterval) {
        self.periods = periods
        self.day = day
    }
}

/// A configured integration (config entry).
struct Integration: Sendable, Hashable, Decodable {
    var entryID: String?
    let domain: String
    let title: String
    let state: String?

    /// Set up, but failing: Maison reloads it on its own.
    var isFailing: Bool { state == "setup_error" || state == "setup_retry" }

    private enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case domain, title, state
    }
}

extension HomeAssistantConnection {
    func layout() async throws -> HomeLayout {
        async let areas = send(["type": "config/area_registry/list"]).decode([Area].self)
        async let entities = send(["type": "config/entity_registry/list"]).decode([EntityRegistryEntry].self)
        async let devices = send(["type": "config/device_registry/list"]).decode([DeviceRegistryEntry].self)
        return try await HomeLayout(areas: areas, entities: entities, devices: devices)
    }
}
