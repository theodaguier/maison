import Foundation

// Every source of data the home can have, by score, and whether it is there. A source is a capability
// (a thermometer, a water meter), never a brand: it is recognised by what the server says a device
// measures. Missing ones say how to get them, and none is required.

enum SourceSection: String, CaseIterable, Sendable {
    case energy, comfort, network, safety, iPhone
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
        "solar": IntegrationNeed(categories: ["energy.solar_batteries"], platforms: ["sensor"]),
        "battery": IntegrationNeed(categories: ["energy.solar_batteries", "energy.ev_charging", "energy.backup_power"], platforms: ["sensor"]),
        "gas": IntegrationNeed(categories: ["energy.meters_monitoring"], platforms: ["sensor"]),
        "water": IntegrationNeed(categories: ["water.meters_leak_detection"], platforms: ["sensor"]),
        "temperature": IntegrationNeed(categories: ["sensors.temperature_humidity", "climate.thermostats_heating"], platforms: ["sensor", "climate"]),
        "humidity": IntegrationNeed(categories: ["sensors.temperature_humidity", "climate.air_purifiers_humidifiers"], platforms: ["sensor", "humidifier"]),
        "carbonDioxide": IntegrationNeed(categories: ["sensors.air_quality"], platforms: ["sensor"]),
        "heating": IntegrationNeed(categories: ["climate.thermostats_heating", "climate.heat_pumps_air_conditioning"], platforms: ["climate"]),
        "windows": IntegrationNeed(categories: ["blinds_curtains"], platforms: ["cover"]),
        "weather": IntegrationNeed(categories: ["weather_alerts.forecasts"], platforms: ["weather"]),
        "router": IntegrationNeed(categories: ["computers_network.routers_network"], platforms: ["device_tracker"]),
        "leak": IntegrationNeed(categories: ["water.meters_leak_detection"], platforms: ["binary_sensor"]),
        "smoke": IntegrationNeed(categories: ["security_safety.smoke_co_alarms"], platforms: ["binary_sensor"]),
        "doors": IntegrationNeed(categories: ["security_safety.locks_access"], platforms: ["lock", "binary_sensor"]),
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
    /// `energy/get_prefs` source types: `solar`, `battery`, `gas`, `water`.
    var energySources: Set<String> = []
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
        if !isDemoHome, let connection { facts.energySources = (try? await connection.energySourceTypes()) ?? [] }
        facts.presenceOn = presence.isEnabled || isTrackedByHomeAssistant
        return facts
    }

    /// Entities measuring `deviceClass`, sensors and binary sensors alike.
    func measuring(_ deviceClasses: Set<String>, domains: Set<String> = ["sensor", "binary_sensor"]) -> [EntityState] {
        states.values.filter { domains.contains($0.domain) && deviceClasses.contains($0.deviceClass ?? "") }.sortedByName()
    }

    func dataSources(_ facts: SourceFacts) -> [DataSource] {
        var sources: [DataSource] = []
        func add(_ id: String, _ section: SourceSection, _ symbol: String, _ title: String, _ missing: String,
                 entities: [EntityState], setup: DataSource.Setup = .device, places: Bool = true) {
            sources.append(DataSource(
                id: id, section: section, symbol: symbol, title: title,
                detail: entities.isEmpty ? missing : places ? whereabouts(entities) : missing,
                state: entities.isEmpty ? .missing : .inPlace("\(entities.count)"),
                setup: setup, entityIDs: entities.map(\.entityID)
            ))
        }

        // Energy
        sources.append(DataSource(
            id: "meter", section: .energy, symbol: "gauge.with.dots.needle.67percent", title: String(localized: "Electricity meter"),
            detail: facts.hasMeter ? String(localized: "Your consumption, measured")
                : facts.gridLinked ? String(localized: "From your grid operator, the day after")
                : String(localized: "Live, with a reader on the meter"),
            state: facts.hasMeter ? .inPlace(String(localized: "Connected")) : facts.gridLinked ? .inPlace(String(localized: "Linked")) : .missing,
            setup: .meter, entityIDs: facts.meterIDs
        ))
        let tariffText: String? = facts.tariff.map { tariff in
            tariff.offPeak.map { String(localized: "Off-peak from \($0.startHour):00 to \($0.endHour):00") } ?? String(localized: "One price")
        } ?? (facts.serverPrice ? String(localized: "Set on the server") : nil)
        sources.append(DataSource(
            id: "tariff", section: .energy, symbol: "eurosign", title: String(localized: "Tariff"),
            detail: tariffText ?? String(localized: "To turn kWh into money"),
            state: tariffText == nil ? .missing : .entered(String(localized: "Entered")), setup: .tariff
        ))
        let meters = Set(facts.meterIDs)
        add("plugs", .energy, "powerplug.fill", String(localized: "Plugs that measure"), String(localized: "What each device uses"),
            entities: devices.filter { $0.deviceClass == "energy" && !meters.contains($0.entityID) && isCumulative($0) })
        sources.append(energySource("solar", "sun.max.fill", String(localized: "Solar panels"), String(localized: "What they produce"), facts))
        sources.append(energySource("battery", "battery.100percent.bolt", String(localized: "Home battery"), String(localized: "What it stores and gives back"), facts))
        add("gas", .energy, "flame.fill", String(localized: "Gas meter"), String(localized: "The gas used each day"),
            entities: measuring(["gas"], domains: ["sensor"]).filter(isCumulative), places: false)
        add("water", .energy, "drop.fill", String(localized: "Water meter"), String(localized: "Litres used, and leaks"),
            entities: measuring(["water"], domains: ["sensor"]).filter(isCumulative), places: false)

        // Comfort
        add("temperature", .comfort, "thermometer.medium", String(localized: "Thermometers"), String(localized: "Comfort, room by room"),
            entities: indoorTemperatureSensors)
        add("humidity", .comfort, "humidity.fill", String(localized: "Humidity"), String(localized: "Too dry or too damp"),
            entities: measuring(["humidity"], domains: ["sensor"]))
        add("carbonDioxide", .comfort, "wind", String(localized: "Air quality"), String(localized: "CO₂, to know when to air"),
            entities: measuring(["carbon_dioxide", "volatile_organic_compounds", "pm25"], domains: ["sensor"]))
        add("heating", .comfort, "heater.vertical.fill", String(localized: "Heating and air conditioning"), String(localized: "The set temperature, room by room"),
            entities: states.values.filter { $0.domain == "climate" }.sortedByName())
        add("windows", .comfort, "window.vertical.open", String(localized: "Windows and shutters"), String(localized: "A window open while heating"),
            entities: measuring(["window"], domains: ["binary_sensor"]) + states.values.filter { $0.domain == "cover" }.sortedByName())
        let weather = states.values.filter { $0.domain == "weather" }.sortedByName()
        sources.append(DataSource(
            id: "weather", section: .comfort, symbol: "cloud.sun.fill", title: String(localized: "Weather"),
            detail: weather.isEmpty ? String(localized: "Outside, to know when to air") : String(localized: "Outside temperature and forecast"),
            state: weather.isEmpty ? .missing : .inPlace(String(localized: "Auto")), setup: .device, entityIDs: weather.map(\.entityID)
        ))

        // Network
        let internet = internetSources
        sources.append(DataSource(
            id: "internet", section: .network, symbol: "network", title: String(localized: "Internet check"),
            detail: internet == nil ? String(localized: "Added by Maison, checked every minute") : String(localized: "Checked every minute"),
            state: internet == nil ? .missing : .inPlace(String(localized: "Auto")), setup: .internetCheck,
            entityIDs: [internet?.connectivity.entityID, internet?.latency?.entityID].compactMap(\.self)
        ))
        let rates = measuring(["data_rate"], domains: ["sensor"])
        // One box gives both, so it's one source, added once.
        let trackers = states.values.filter { $0.domain == "device_tracker" && $0.attributes["source_type"]?.stringValue == "router" }
        let connected = trackers.count { $0.state == "home" }
        sources.append(DataSource(
            id: "router", section: .network, symbol: "wifi.router.fill", title: String(localized: "Box or router"),
            detail: trackers.isEmpty ? String(localized: "Throughput and connected devices") : String(localized: "Throughput, and \(connected) devices connected"),
            state: rates.isEmpty && trackers.isEmpty ? .missing : .inPlace(String(localized: "Connected")), setup: .device,
            entityIDs: rates.map(\.entityID)
        ))

        // Safety
        add("leak", .safety, "drop.triangle.fill", String(localized: "Leak detectors"), String(localized: "Under the sink, behind the washing machine"),
            entities: measuring(["moisture"], domains: ["binary_sensor"]))
        add("smoke", .safety, "smoke.fill", String(localized: "Smoke detectors"), String(localized: "Smoke and carbon monoxide"),
            entities: measuring(["smoke", "carbon_monoxide", "gas"], domains: ["binary_sensor"]))
        add("doors", .safety, "door.left.hand.closed", String(localized: "Doors and locks"), String(localized: "Open, closed, locked"),
            entities: measuring(["door", "garage_door", "opening"], domains: ["binary_sensor"]) + states.values.filter { $0.domain == "lock" }.sortedByName())

        // iPhone
        sources.append(DataSource(
            id: "presence", section: .iPhone, symbol: "location.fill", title: String(localized: "Presence"),
            detail: String(localized: "Arrivals and departures of the household"),
            state: facts.presenceOn ? .inPlace(String(localized: "On")) : .missing, setup: .presence
        ))
        return sources
    }

    /// The share of each score's sources that are there; Safety and the iPhone aren't scores.
    static func coverage(of sources: [DataSource]) -> [SourceCoverage] {
        [SourceSection.comfort, .energy, .network].map { section in
            let all = sources.filter { $0.section == section }
            let main = ["comfort": "temperature", "energy": "meter", "network": "internet"][section.rawValue]
            return SourceCoverage(section: section, inPlace: all.count(where: \.isInPlace), total: all.count,
                                  isMeasured: all.first { $0.id == main }?.isInPlace ?? false)
        }
    }

    private func energySource(_ type: String, _ symbol: String, _ title: String, _ missing: String, _ facts: SourceFacts) -> DataSource {
        let there = facts.energySources.contains(type)
        return DataSource(id: type, section: .energy, symbol: symbol, title: title,
                          detail: there ? String(localized: "In the server’s energy settings") : missing,
                          state: there ? .inPlace(String(localized: "Connected")) : .missing, setup: .device)
    }

    private func isCumulative(_ entity: EntityState) -> Bool {
        ["total_increasing", "total"].contains(entity.attributes["state_class"]?.stringValue ?? "")
    }

    /// "Living room and bedroom", or the names when they have no room.
    private func whereabouts(_ entities: [EntityState]) -> String {
        let rooms = entities.compactMap { area(of: $0)?.name }.uniqued()
        let names = rooms.isEmpty ? entities.map(\.name).uniqued() : rooms
        let shown = Array(names.prefix(3))
        let text = shown.formatted(.list(type: .and))
        return names.count > 3 ? String(localized: "\(text) and \(names.count - 3) more") : text
    }
}

extension Array where Element: Hashable {
    /// In order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension HomeAssistantConnection {
    /// The kinds of sources in the server's energy settings: `grid`, `solar`, `battery`, `gas`, `water`.
    func energySourceTypes() async throws -> Set<String> {
        let prefs = try await send(["type": "energy/get_prefs"])
        return Set((prefs["energy_sources"]?.arrayValue ?? []).compactMap { $0["type"]?.stringValue })
    }
}
