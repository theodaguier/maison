import Foundation

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
    /// What the entity is within its integration ("filter_life"), the same in every language.
    var translationKey: String?

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
        case translationKey = "translation_key"
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

/// Reads the registries into the layout.
extension HomeLayout {
    init(areas: [Area], entities: [EntityRegistryEntry], devices: [DeviceRegistryEntry]) {
        self.init()
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
            if let key = entry.translationKey {
                translationKeyByEntity[entry.entityID] = key
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
