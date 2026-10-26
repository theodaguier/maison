import Foundation

/// The three scores at one moment, with what each fiche needs to explain them.
struct HomeScores: Sendable, Equatable {
    var comfort: ComfortScore?
    var energy: EnergyScore?
    var network: NetworkScore?
    /// Nothing measures the internet yet (no Ping integration in Home Assistant).
    var hasNetworkSource = false
    /// An electricity meter reaches the server, even if it has no habit to compare with yet.
    var hasElectricityMeter = false
    /// What Maison noticed, most valuable first.
    var findings: [Finding] = []
    /// What the home screen shows under the scores, most urgent first.
    var highlights: [Highlight] = []
    /// The price of a kWh and what the day and the month cost, when a price is known.
    var energyPrice: EnergyPrice?
    var energyCost: EnergyCost?
    var computedAt: Date
}

/// The household's comfort range, when the person set one in Settings.
enum ComfortRangeSetting {
    static let lowerKey = "comfortRangeLower"
    static let upperKey = "comfortRangeUpper"

    static func range(in defaults: UserDefaults = .standard) -> ClosedRange<Double>? {
        guard let lower = defaults.object(forKey: lowerKey) as? Double,
              let upper = defaults.object(forKey: upperKey) as? Double, lower < upper else { return nil }
        return lower...upper
    }

    /// Where the score starts until three days of readings teach the household's own range,
    /// in the unit the server measures in.
    static func starting(fahrenheit: Bool) -> ClosedRange<Double> { fahrenheit ? 66...72 : 19...22 }

    /// The bounds the person can set a range within, and the step, in the server's unit.
    static func editable(fahrenheit: Bool) -> (bounds: ClosedRange<Double>, step: Double) {
        fahrenheit ? (50...90, 1) : (10...32, 0.5)
    }

    static func set(_ range: ClosedRange<Double>, in defaults: UserDefaults = .standard) {
        defaults.set(range.lowerBound, forKey: lowerKey)
        defaults.set(range.upperBound, forKey: upperKey)
    }

    /// The range Comfort scores against: the one entered, else the one learned, else the starting one.
    static func resolve(entered: ClosedRange<Double>?, hourlyMeans: [Double],
                        fahrenheit: Bool = false) -> (range: ClosedRange<Double>, origin: ValueOrigin, isStarting: Bool) {
        if let entered { return (entered, .entered, false) }
        if let learned = learned(from: hourlyMeans) { return (learned, .estimated, false) }
        return (starting(fahrenheit: fahrenheit), .estimated, true)
    }

    /// The 10th to 90th percentile of the previous week's hourly means, to the half degree.
    /// `nil` with fewer than three days of readings.
    static func learned(from hourlyMeans: [Double]) -> ClosedRange<Double>? {
        guard hourlyMeans.count >= 72 else { return nil }
        let lower = (percentile(hourlyMeans, 0.1) * 2).rounded(.down) / 2
        let upper = (percentile(hourlyMeans, 0.9) * 2).rounded(.up) / 2
        return lower < upper ? lower...upper : nil
    }
}

extension HomeStore {
    /// One temperature sensor per room that has one, in room order.
    var roomTemperatureSensors: [(area: Area, sensor: EntityState)] {
        let sensors = indoorTemperatureSensors
        return rooms.compactMap { area in
            sensors.first { self.area(of: $0)?.id == area.id }.map { (area, $0) }
        }
    }

    /// The thermometers Comfort counts: one per room, then each one not in a room yet, under its own name.
    var comfortSensors: [(id: String, name: String, sensor: EntityState)] {
        let placed = roomTemperatureSensors
        let placedIDs = Set(placed.map(\.sensor.entityID))
        let unplaced = indoorTemperatureSensors.filter { area(of: $0) == nil && !placedIDs.contains($0.entityID) }
        return placed.map { ($0.area.id, $0.area.name, $0.sensor) } + unplaced.sortedByName().map { ($0.entityID, $0.name, $0) }
    }

    /// The internet check Home Assistant's Ping integration provides, and its average round trip.
    var internetSources: (connectivity: EntityState, latency: EntityState?)? {
        let ping = states.values.filter { layout.platformByEntity[$0.entityID] == "ping" }
        guard let connectivity = ping.filter({ $0.domain == "binary_sensor" }).min(by: { $0.entityID < $1.entityID }) else { return nil }
        // Ping reports minimum, average, maximum and deviation; the average sits just under the maximum.
        let roundTrips = ping.filter { $0.domain == "sensor" && $0.unit == "ms" && $0.numericState != nil }
            .sorted { $0.numericState! < $1.numericState! }
        return (connectivity, roundTrips.count >= 2 ? roundTrips[roundTrips.count - 2] : roundTrips.first)
    }

    /// The box's or router's own internet check, from its integration: what Network counts when
    /// Home Assistant has no Ping check, such as for a resident who can't add one.
    var routerInternet: EntityState? {
        // The box itself: an integration in the routers' category that also reports throughput or the
        // devices it sees. A VPN's or a DNS filter's own connectivity sensors are about something else.
        let boxes = Set(states.values.compactMap { entity -> String? in
            guard entity.deviceClass == "data_rate" || (entity.domain == "device_tracker" && entity.attributes["source_type"]?.stringValue == "router"),
                  let platform = layout.platformByEntity[entity.entityID], IntegrationCategories.isRouter(platform) else { return nil }
            return platform
        })
        return states.values
            .filter { $0.domain == "binary_sensor" && $0.deviceClass == "connectivity" }
            .filter { layout.platformByEntity[$0.entityID].map(boxes.contains) ?? false }
            .min { $0.entityID < $1.entityID }
    }

    func loadScores(now: Date = .now) async -> HomeScores {
        let window = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        let weekAgo = now.addingTimeInterval(-8 * 86_400)
        async let comfort = comfortScore(window: window, weekAgo: weekAgo)
        async let energy = energyScore(now: now, weekAgo: weekAgo)
        async let meters = electricityMeters()
        async let findings = findings(now: now)
        async let network = networkScore(window: window, weekAgo: weekAgo)
        var scores = await HomeScores(
            comfort: comfort,
            energy: energy,
            network: network,
            hasNetworkSource: internetSources != nil || routerInternet != nil,
            hasElectricityMeter: !meters.ids.isEmpty,
            findings: findings,
            computedAt: now
        )
        let inputs = await highlightInputs(for: scores)
        scores.energyPrice = inputs.price
        scores.energyCost = inputs.cost
        scores.highlights = Highlights.compute(scores: scores, inputs: inputs)
        return scores
    }

    private func comfortScore(window: DateInterval, weekAgo: Date) async -> ComfortScore? {
        let sensors = comfortSensors
        guard !sensors.isEmpty else { return nil }
        let resolved: (range: ClosedRange<Double>, origin: ValueOrigin, isStarting: Bool)
        if isDemoHome {
            resolved = (20...24, .entered, false)
        } else if let entered = ComfortRangeSetting.range() {
            resolved = ComfortRangeSetting.resolve(entered: entered, hourlyMeans: [])
        } else {
            var means: [Double] = []
            for (_, _, sensor) in sensors {
                let points = await statistics(of: sensor.entityID, since: weekAgo, period: "hour")
                var values = points.filter { $0.start < window.start }.compactMap(\.mean)
                if values.isEmpty {
                    // A sensor without `state_class` keeps no statistics: read its raw history instead.
                    values = await changes(of: sensor.entityID, since: weekAgo)
                        .filter { $0.date < window.start }
                        .compactMap { Double($0.state) }
                }
                means += values
            }
            // Without three days to learn from, a usual range gives a score from the first day.
            resolved = ComfortRangeSetting.resolve(entered: nil, hourlyMeans: means, fahrenheit: serverConfig?.usesFahrenheit ?? false)
        }
        var rooms: [(id: String, name: String, series: TimeSeries)] = []
        for (id, name, sensor) in sensors {
            var series = await changes(of: sensor.entityID, since: window.start)
            // A sensor that hasn't changed since it was added has no history yet: its current reading counts.
            if series.isEmpty, sensor.numericState != nil {
                series = [StateChange(state: sensor.state, date: max(sensor.lastChanged ?? window.start, window.start))]
            }
            rooms.append((id, name, TimeSeries(changes: series)))
        }
        var score = ComfortScore.compute(rooms: rooms, range: resolved.range, rangeOrigin: resolved.origin, window: window)
        score?.rangeIsStarting = resolved.isStarting
        return score
    }

    func energyScore(now: Date, weekAgo: Date) async -> EnergyScore? {
        let meters = await electricityMeters()
        guard !meters.ids.isEmpty else { return nil }
        var series: [(id: String, byHour: [Date: Double])] = []
        for meter in meters.ids {
            var byHour: [Date: Double] = [:]
            // A week for the habit, and the whole month for its cost.
            let monthStart = Calendar.current.dateInterval(of: .month, for: now)?.start ?? weekAgo
            for point in await statistics(of: meter, since: min(Calendar.current.startOfDay(for: weekAgo), monthStart), period: "hour") {
                if let change = point.change { byHour[point.start, default: 0] += max(0, change) }
            }
            series.append((meter, byHour))
        }
        let byHour: [Date: Double]
        let used: [String]
        if meters.addUp {
            byHour = series.reduce(into: [:]) { total, meter in total.merge(meter.byHour, uniquingKeysWith: +) }
            used = meters.ids
        } else {
            // Without the Energy dashboard, a plug's own total would count twice: the home's meter is
            // the one that used the most.
            guard let largest = series.max(by: { $0.byHour.values.reduce(0, +) < $1.byHour.values.reduce(0, +) }) else { return nil }
            byHour = largest.byHour
            used = [largest.id]
        }
        let unit = used.lazy.compactMap { self.states[$0]?.unit }.first ?? "kWh"
        var score = EnergyScore.compute(hourly: byHour.map { (start: $0.key, value: $0.value) }, unit: unit, now: now)
        score?.meterIDs = used
        score?.meterIsConfirmed = meters.addUp
        return score
    }

    /// Sets the meter Maison picked as the home's meter in Home Assistant's Energy dashboard, so the
    /// server counts it too. Only an administrator can; `false` when it didn't work.
    func confirmMeter(_ id: String) async -> Bool {
        if isDemoHome { return true }
        guard currentUser?.isAdmin == true, let connection else { return false }
        return (try? await connection.setGridMeter(id)) != nil
    }

    private func networkScore(window: DateInterval, weekAgo: Date) async -> NetworkScore? {
        // Ping first: it also times the round trip. Otherwise the router says whether the line is up.
        guard let connectivitySensor = internetSources?.connectivity ?? routerInternet else { return nil }
        let connectivity = await changes(of: connectivitySensor.entityID, since: window.start)
        var today: TimeSeries?, past: TimeSeries?
        if let latency = internetSources?.latency {
            let week = await changes(of: latency.entityID, since: weekAgo)
            today = TimeSeries(changes: week.filter { $0.date >= window.start })
            past = TimeSeries(changes: week.filter { $0.date < window.start })
        }
        return NetworkScore.compute(connectivity: connectivity, latency: today, pastLatency: past, window: window)
    }
}
