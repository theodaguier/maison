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
            if !entry.isVisible {
                hiddenEntities.insert(entry.entityID)
            }
        }
    }
}

struct HomeAssistantUser: Sendable, Hashable, Decodable {
    let name: String
    let isAdmin: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case isAdmin = "is_admin"
    }
}

struct ServerConfig: Sendable, Hashable, Decodable {
    let locationName: String?
    let version: String?
    let externalURL: String?
    let internalURL: String?

    private enum CodingKeys: String, CodingKey {
        case locationName = "location_name"
        case version
        case externalURL = "external_url"
        case internalURL = "internal_url"
    }
}

/// A configured integration (config entry).
struct Integration: Sendable, Hashable, Decodable {
    let domain: String
    let title: String
    let state: String?
}

extension HomeAssistantConnection {
    func layout() async throws -> HomeLayout {
        async let areas = send(["type": "config/area_registry/list"]).decode([Area].self)
        async let entities = send(["type": "config/entity_registry/list"]).decode([EntityRegistryEntry].self)
        async let devices = send(["type": "config/device_registry/list"]).decode([DeviceRegistryEntry].self)
        return try await HomeLayout(areas: areas, entities: entities, devices: devices)
    }
}
