import Foundation

// Every source of data the home can have, by score, and whether it is there. A source is a capability
// (a thermometer, a water meter), never a brand: it is recognised by what the server says a device
// measures. Missing ones say how to get them, and none is required.

enum SourceSection: String, CaseIterable, Sendable {
    case energy, comfort, network, iPhone
}

struct DataSource: Identifiable, Hashable, Sendable {
    let id: String
    let section: SourceSection
    let symbol: String
    let title: String
    /// What it brings, or what is there ("Living room and bedroom").
    let detail: String
    let state: State
    let setup: Setup
    /// The entities that provide it, for its page.
    var entityIDs: [String] = []

    /// The integrations that can provide it: their Home Assistant category and the kind of entity it reads,
    /// so its page offers those, not a calendar or a box with an alarm. `nil` when Maison's own way is the
    /// one (the internet check).
    var need: IntegrationNeed? { Self.needs[id] }

    static let needs: [String: IntegrationNeed] = [
        "meter": IntegrationNeed(categories: ["energy.meters_monitoring"], platforms: ["sensor"]),
        "tariff": IntegrationNeed(categories: ["energy.energy_prices"], platforms: ["sensor"]),
        "plugs": IntegrationNeed(categories: ["plugs_switches"], platforms: ["sensor"]),
        "water": IntegrationNeed(categories: ["water.meters_leak_detection"], platforms: ["sensor"]),
        "temperature": IntegrationNeed(categories: ["sensors.temperature_humidity", "climate.thermostats_heating"], platforms: ["sensor", "climate"]),
        "humidity": IntegrationNeed(categories: ["sensors.temperature_humidity", "climate.air_purifiers_humidifiers"], platforms: ["sensor", "humidifier"]),
        "carbonDioxide": IntegrationNeed(categories: ["sensors.air_quality"], platforms: ["sensor"]),
        "weather": IntegrationNeed(categories: ["weather_alerts.forecasts"], platforms: ["weather"]),
        "router": IntegrationNeed(categories: ["computers_network.routers_network"], platforms: ["device_tracker"]),
        "presence": IntegrationNeed(categories: ["presence_location.phones_companion_apps", "presence_location.trackers"], platforms: ["device_tracker"]),
    ]

    enum State: Hashable, Sendable {
        /// Measured by a device or a service; the value says how many or how.
        case inPlace(String)
        /// Entered by the person.
        case entered(String)
        case missing
    }

    /// How a missing source is added.
    enum Setup: Hashable, Sendable {
        /// The meter: the grid operator, a reader, a clamp.
        case meter
        case tariff
        /// Maison adds it to the server by itself.
        case internetCheck
        case presence
        /// A device: Maison adds it once it is on the network, or the person looks for its brand.
        case device
    }

    var isInPlace: Bool { state != .missing }
}

/// How far a score rests on measurements.
struct SourceCoverage: Equatable, Sendable {
    let section: SourceSection
    let inPlace: Int
    let total: Int
    /// The score's main input is measured rather than estimated.
    let isMeasured: Bool
}

/// What the home has, gathered once: everything `HomeStore.dataSources` needs.
struct SourceFacts: Sendable {
    var meterIDs: [String] = []
    var hasMeter: Bool { !meterIDs.isEmpty }
    var gridLinked = false
    var gridOperatorName: String?
    var tariff: EnergyTariff?
    var serverPrice = false
    var presenceOn = false
}

extension HomeStore {
    func sourceFacts() async -> SourceFacts {
        var facts = SourceFacts()
        facts.meterIDs = await electricityMeters().ids
        facts.gridLinked = GridLink.load() != nil
        if MaisonRelay.url != nil { facts.gridOperatorName = GridOperator.supported(in: serverConfig?.country)?.name }
        facts.tariff = energyTariff
        facts.serverPrice = await serverEnergyPrice() != nil
        facts.presenceOn = presence.isEnabled || isTrackedByHomeAssistant
        return facts
    }

    /// Entities measuring `deviceClass`, sensors and binary sensors alike.
    func measuring(_ deviceClasses: Set<String>, domains: Set<String> = ["sensor", "binary_sensor"]) -> [EntityState] {
        states.values.filter { domains.contains($0.domain) && deviceClasses.contains($0.deviceClass ?? "") }.sortedByName()
    }

    /// Only the sources something in the app uses, each saying what it makes work. Safety comes with
    /// the alerts.
    func dataSources(_ facts: SourceFacts) -> [DataSource] {
        var sources: [DataSource] = []
        func add(_ id: String, _ section: SourceSection, _ symbol: String, _ title: String, _ use: String,
                 entities: [EntityState], setup: DataSource.Setup = .device) {
            sources.append(DataSource(id: id, section: section, symbol: symbol, title: title, detail: use,
                                      state: entities.isEmpty ? .missing : .inPlace("\(entities.count)"),
                                      setup: setup, entityIDs: entities.map(\.entityID)))
        }

        // Energy
        sources.append(DataSource(
            id: "meter", section: .energy, symbol: "gauge.with.dots.needle.67percent", title: String(localized: "Electricity meter"),
            detail: String(localized: "The Energy score"),
            state: facts.hasMeter ? .inPlace(String(localized: "Connected")) : facts.gridLinked ? .inPlace(String(localized: "Linked")) : .missing,
            setup: .meter, entityIDs: facts.meterIDs
        ))
        let tariffEntered = facts.tariff != nil || facts.serverPrice
        sources.append(DataSource(
            id: "tariff", section: .energy, symbol: "eurosign", title: String(localized: "Tariff"),
            detail: String(localized: "The cost, and the off-peak findings"),
            state: tariffEntered ? .entered(String(localized: "Entered")) : .missing, setup: .tariff
        ))
        let meters = Set(facts.meterIDs)
        add("plugs", .energy, "powerplug.fill", String(localized: "Plugs that measure"), String(localized: "Use by device, and the findings"),
            entities: devices.filter { $0.deviceClass == "energy" && !meters.contains($0.entityID) && isCumulative($0) })
        add("water", .energy, "drop.fill", String(localized: "Water meter"), String(localized: "The Water tab"),
            entities: measuring(["water"], domains: ["sensor"]).filter(isCumulative))

        // Comfort
        add("temperature", .comfort, "thermometer.medium", String(localized: "Thermometers"), String(localized: "The Comfort score"),
            entities: indoorTemperatureSensors)
        add("humidity", .comfort, "humidity.fill", String(localized: "Humidity"), String(localized: "Humidity in each room"),
            entities: measuring(["humidity"], domains: ["sensor"]))
        add("carbonDioxide", .comfort, "wind", String(localized: "Air quality"), String(localized: "When to air"),
            entities: measuring(["carbon_dioxide"], domains: ["sensor"]))
        let weather = states.values.filter { $0.domain == "weather" }.sortedByName()
        sources.append(DataSource(
            id: "weather", section: .comfort, symbol: "cloud.sun.fill", title: String(localized: "Weather"),
            detail: String(localized: "When to air, and the weather outside"),
            state: weather.isEmpty ? .missing : .inPlace(String(localized: "Auto")), setup: .device, entityIDs: weather.map(\.entityID)
        ))

        // Network
        let internet = internetSources
        sources.append(DataSource(
            id: "internet", section: .network, symbol: "network", title: String(localized: "Internet check"),
            detail: String(localized: "The Network score"),
            state: internet == nil ? .missing : .inPlace(String(localized: "Auto")), setup: .internetCheck,
            entityIDs: [internet?.connectivity.entityID, internet?.latency?.entityID].compactMap(\.self)
        ))
        // One box gives both, so it's one source, added once.
        let rates = measuring(["data_rate"], domains: ["sensor"])
        let trackers = states.values.filter { $0.domain == "device_tracker" && $0.attributes["source_type"]?.stringValue == "router" }
        sources.append(DataSource(
            id: "router", section: .network, symbol: "wifi.router.fill", title: String(localized: "Box or router"),
            detail: String(localized: "Throughput, and the devices connected"),
            state: rates.isEmpty && trackers.isEmpty ? .missing : .inPlace(String(localized: "Connected")), setup: .device,
            entityIDs: rates.map(\.entityID)
        ))

        // iPhone
        sources.append(DataSource(
            id: "presence", section: .iPhone, symbol: "location.fill", title: String(localized: "Presence"),
            detail: String(localized: "Rules when you leave or come home"),
            state: facts.presenceOn ? .inPlace(String(localized: "On")) : .missing, setup: .presence
        ))
        return sources
    }

    /// The share of each score's sources that are there; the iPhone isn't a score.
    static func coverage(of sources: [DataSource]) -> [SourceCoverage] {
        [SourceSection.comfort, .energy, .network].map { section in
            let all = sources.filter { $0.section == section }
            let main = ["comfort": "temperature", "energy": "meter", "network": "internet"][section.rawValue]
            return SourceCoverage(section: section, inPlace: all.count(where: \.isInPlace), total: all.count,
                                  isMeasured: all.first { $0.id == main }?.isInPlace ?? false)
        }
    }

    private func isCumulative(_ entity: EntityState) -> Bool {
        ["total_increasing", "total"].contains(entity.attributes["state_class"]?.stringValue ?? "")
    }
}
