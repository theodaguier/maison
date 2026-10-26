import Foundation

// What the scores' facts are computed from, read from the store: findings, the fiches' data, the
// highlights' inputs. Main-actor glue around the intelligence layer.

extension HomeStore {
    /// The switch that powers the same device as `entity` (a plug, a contactor), if any.
    func powerSwitch(for entity: EntityState) -> EntityState? {
        guard let device = layout.deviceByEntity[entity.entityID] else { return nil }
        return states.values.first { $0.domain == "switch" && layout.deviceByEntity[$0.entityID] == device }
    }

    /// Findings over the last complete day, ignored ones left out.
    func findings(now: Date = .now) async -> [Finding] {
        guard let tariff = isDemoHome ? DemoHome.tariff : EnergyTariff.load(), tariff.offPeak != nil else { return [] }
        let currency = serverConfig?.currency ?? Locale.current.currency?.identifier ?? "EUR"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }
        let meters = await electricityMeters().ids
        var found: [Finding] = []
        for sensor in devices where sensor.deviceClass == "energy" && !meters.contains(sensor.entityID)
            && ["total_increasing", "total"].contains(sensor.attributes["state_class"]?.stringValue ?? "") {
            var usage: [Int: Double] = [:]
            for point in await statistics(of: sensor.entityID, since: yesterday, period: "hour") where point.start < today {
                usage[calendar.component(.hour, from: point.start), default: 0] += max(0, point.change ?? 0)
            }
            let name = powerSwitch(for: sensor)?.name ?? sensor.name
            if let finding = PeakHoursFinding.compute(deviceID: sensor.entityID, deviceName: name, usage: usage, tariff: tariff,
                                                      currency: currency, switchEntity: powerSwitch(for: sensor)?.entityID),
                !FindingFeedback.isIgnored(finding.id) {
                found.append(finding)
            }
        }
        return found.sorted { $0.yearlyValue > $1.yearlyValue }
    }

    var outdoorWeather: OutdoorWeather? {
        guard let weather = states.values.filter({ $0.domain == "weather" }).min(by: { $0.entityID < $1.entityID }),
              let temperature = weather.attributes["temperature"]?.doubleValue else { return nil }
        return OutdoorWeather(temperature: temperature, humidity: weather.attributes["humidity"]?.doubleValue, condition: weather.state)
    }

    /// Each room's indoor CO₂, when a sensor measures it.
    var roomCarbonDioxide: [(room: String, ppm: Double)] {
        rooms.compactMap { room in averageValue(of: "carbon_dioxide", in: room).map { (room.name, $0) } }
    }

    /// The price from Home Assistant's Energy dashboard, otherwise the one entered in Maison.
    func energyPrice() async -> EnergyPrice? {
        let currency = serverConfig?.currency ?? Locale.current.currency?.identifier ?? "EUR"
        if isDemoHome { return EnergyPrice(perKilowattHour: DemoHome.tariff.price, currency: "EUR", origin: .entered, tariff: DemoHome.tariff) }
        if let fromServer = await serverEnergyPrice() { return EnergyPrice(perKilowattHour: fromServer, currency: currency, origin: .entered) }
        return EnergyTariff.load().map { EnergyPrice(perKilowattHour: $0.price, currency: currency, origin: .entered, tariff: $0) }
    }

    /// Energy totals that belong to a device (a plug, an appliance), not to the home's meter.
    func deviceEnergy(day: Date, asOf: Date, excluding meters: [String]) async -> [DeviceEnergy] {
        let sensors = devices.filter {
            $0.deviceClass == "energy" && ["total_increasing", "total"].contains($0.attributes["state_class"]?.stringValue ?? "")
                && !meters.contains($0.entityID)
        }
        var result: [DeviceEnergy] = []
        for sensor in sensors {
            let points = await statistics(of: sensor.entityID, since: day, period: "hour")
            let used = points.filter { $0.start < asOf }.compactMap(\.change).reduce(0) { $0 + max(0, $1) }
            if used > 0.01 { result.append(DeviceEnergy(id: sensor.entityID, name: sensor.name, kilowattHours: used)) }
        }
        return result.sorted { $0.kilowattHours > $1.kilowattHours }
    }

    /// Water used since `day`, in the meter's unit, when a water meter exists.
    func waterUsed(since day: Date) async -> (value: Double, unit: String)? {
        guard let meter = devices.first(where: {
            $0.deviceClass == "water" && ["total_increasing", "total"].contains($0.attributes["state_class"]?.stringValue ?? "")
        }) else { return nil }
        let used = await statistics(of: meter.entityID, since: day, period: "hour").compactMap(\.change).reduce(0) { $0 + max(0, $1) }
        return (used, meter.unit ?? "L")
    }

    /// Throughput sensors (the router's UPnP integration, a speed test) and the devices it sees.
    func routerReadings(since start: Date) async -> RouterReadings {
        var readings = RouterReadings()
        let rates = devices.filter { $0.deviceClass == "data_rate" && $0.numericState != nil }
        // Download and upload aren't told apart by name: the faster of the two is the download.
        if let download = rates.max(by: { $0.numericState! < $1.numericState! }) {
            readings.download = TimeSeries(changes: await changes(of: download.entityID, since: start))
                .segments(in: DateInterval(start: start, end: .now)).map { (date: $0.interval.start, value: $0.value) }
            readings.downloadUnit = download.unit
            readings.upload = rates.filter { $0.entityID != download.entityID }.compactMap(\.numericState).max()
        }
        let trackers = states.values.filter { $0.domain == "device_tracker" && $0.attributes["source_type"]?.stringValue == "router" }
        if !trackers.isEmpty { readings.connectedDevices = trackers.count { $0.state == "home" } }
        return readings
    }

    /// Climates heating at this moment.
    var heatingClimates: [EntityState] { climates(running: "heating", mode: "heat") }

    /// Climates cooling at this moment.
    var coolingClimates: [EntityState] { climates(running: "cooling", mode: "cool") }

    /// Climates doing `action` now; without `hvac_action`, the ones set to `mode`.
    private func climates(running action: String, mode: String) -> [EntityState] {
        devices.filter { entity in
            guard entity.domain == "climate" else { return false }
            if let current = entity.attributes["hvac_action"]?.stringValue { return current == action }
            return entity.state == mode
        }
    }

    /// Whether someone is home; `nil` when no person is tracked.
    var someoneHome: Bool? {
        let people = states.values.filter { $0.domain == "person" && $0.state != "unknown" && $0.state != "unavailable" }
        guard !people.isEmpty else { return nil }
        return people.contains { $0.state == "home" }
    }

    /// Windows open in a room that is heated or cooled, or anywhere when the climate has no room.
    func openWindows(whileRunning climates: [EntityState]) -> [EntityState] {
        guard !climates.isEmpty else { return [] }
        let heatedRooms = Set(climates.compactMap { area(of: $0)?.id })
        return measuring(["window"], domains: ["binary_sensor"]).filter { window in
            window.state == "on" && (heatedRooms.isEmpty || area(of: window).map { heatedRooms.contains($0.id) } ?? true)
        }
    }

    /// What the highlights are computed from, besides the scores.
    func highlightInputs(for scores: HomeScores) async -> HighlightInputs {
        let heating = heatingClimates
        let cooling = coolingClimates
        var inputs = HighlightInputs(
            heating: heating.map(\.entityID),
            cooling: cooling.map(\.entityID),
            someoneHome: someoneHome,
            openWindows: openWindows(whileRunning: heating + cooling).map(\.name),
            carbonDioxide: roomCarbonDioxide,
            outdoor: outdoorWeather,
            hasThermometer: !comfortSensors.isEmpty,
            meterProposalSeen: MeterProposalSetting.wasSeen
        )
        if let energy = scores.energy {
            let meters = await electricityMeters().ids
            inputs.devices = await deviceEnergy(day: energy.day, asOf: energy.asOf, excluding: meters)
            inputs.price = await energyPrice()
            if let price = inputs.price {
                inputs.cost = EnergyCost.compute(hourly: energy.history, price: price.price(atHour:), day: energy.day, asOf: energy.asOf)
            }
        } else {
            inputs.price = await energyPrice()
        }
        let trackers = states.values.filter { $0.domain == "device_tracker" && $0.attributes["source_type"]?.stringValue == "router" }
        if !trackers.isEmpty { inputs.connectedDevices = trackers.count { $0.state == "home" } }
        return inputs
    }
}
