import Foundation

/// A Home Assistant area, shown as a room.
public struct Area: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    /// The room's icon in Home Assistant ("mdi:sofa"), which says what it is for.
    public var icon: String?

    public init(id: String, name: String, icon: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case id = "area_id"
        case name
        case icon
    }
}

/// Everything the registries say about how entities are organised.
public struct HomeLayout: Sendable, Hashable, Codable {
    public var areas: [Area] = []
    public var areaByEntity: [String: String] = [:]
    public var deviceByEntity: [String: String] = [:]
    public var hiddenEntities: Set<String> = []
    public var platformByEntity: [String: String] = [:]
    public var translationKeyByEntity: [String: String] = [:]

    public init() {}
}

/// The server's general settings.
public struct ServerConfig: Sendable, Hashable, Decodable {
    public let locationName: String?
    public let version: String?
    public let externalURL: String?
    public let internalURL: String?
    /// ISO 3166 code set in Home Assistant's general settings ("FR").
    public var country: String?
    /// ISO 4217 code ("EUR"), the currency Home Assistant counts energy costs in.
    public var currency: String?
    /// "°C" or "°F", from Home Assistant's unit system.
    public var temperatureUnit: String?

    public var usesFahrenheit: Bool { temperatureUnit == "°F" }

    public init(
        locationName: String?,
        version: String?,
        externalURL: String?,
        internalURL: String?,
        country: String? = nil,
        currency: String? = nil,
        temperatureUnit: String? = nil
    ) {
        self.locationName = locationName
        self.version = version
        self.externalURL = externalURL
        self.internalURL = internalURL
        self.country = country
        self.currency = currency
        self.temperatureUnit = temperatureUnit
    }

    private enum CodingKeys: String, CodingKey {
        case locationName = "location_name"
        case version
        case externalURL = "external_url"
        case internalURL = "internal_url"
        case country, currency
        case unitSystem = "unit_system"
    }

    private struct UnitSystem: Decodable {
        let temperature: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        externalURL = try container.decodeIfPresent(String.self, forKey: .externalURL)
        internalURL = try container.decodeIfPresent(String.self, forKey: .internalURL)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        temperatureUnit = try? container.decodeIfPresent(UnitSystem.self, forKey: .unitSystem)?.temperature
    }
}
