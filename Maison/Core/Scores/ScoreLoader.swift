import Foundation

/// The three scores at one moment, with what each fiche needs to explain them.
struct HomeScores: Sendable, Equatable {
    var comfort: ComfortScore?
    var energy: EnergyScore?
    var network: NetworkScore?
    /// Nothing measures the internet yet (no Ping integration in Home Assistant).
    var hasNetworkSource = false
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

    static func set(_ range: ClosedRange<Double>, in defaults: UserDefaults = .standard) {
        defaults.set(range.lowerBound, forKey: lowerKey)
        defaults.set(range.upperBound, forKey: upperKey)
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

    /// The internet check Home Assistant's Ping integration provides, and its average round trip.
    var internetSources: (connectivity: EntityState, latency: EntityState?)? {
        let ping = states.values.filter { layout.platformByEntity[$0.entityID] == "ping" }
        guard let connectivity = ping.filter({ $0.domain == "binary_sensor" }).min(by: { $0.entityID < $1.entityID }) else { return nil }
        // Ping reports minimum, average, maximum and deviation; the average sits just under the maximum.
        let roundTrips = ping.filter { $0.domain == "sensor" && $0.unit == "ms" && $0.numericState != nil }
            .sorted { $0.numericState! < $1.numericState! }
        return (connectivity, roundTrips.count >= 2 ? roundTrips[roundTrips.count - 2] : roundTrips.first)
    }

    func loadScores(now: Date = .now) async -> HomeScores {
        let window = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        let weekAgo = now.addingTimeInterval(-8 * 86_400)
        async let comfort = comfortScore(window: window, weekAgo: weekAgo)
        async let energy = energyScore(now: now, weekAgo: weekAgo)
        async let network = networkScore(window: window, weekAgo: weekAgo)
        return await HomeScores(
            comfort: comfort,
            energy: energy,
            network: network,
            hasNetworkSource: internetSources != nil,
            computedAt: now
        )
    }

    private func comfortScore(window: DateInterval, weekAgo: Date) async -> ComfortScore? {
        let sensors = roomTemperatureSensors
        guard !sensors.isEmpty else { return nil }
        var range: ClosedRange<Double>
        var origin: ValueOrigin
        if isDemoHome {
            (range, origin) = (20...24, .entered)
        } else if let entered = ComfortRangeSetting.range() {
            (range, origin) = (entered, .entered)
        } else {
            var means: [Double] = []
            for (_, sensor) in sensors {
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
            guard let learned = ComfortRangeSetting.learned(from: means) else { return nil }
            (range, origin) = (learned, .estimated)
        }
        var rooms: [(id: String, name: String, series: TimeSeries)] = []
        for (area, sensor) in sensors {
            rooms.append((area.id, area.name, TimeSeries(changes: await changes(of: sensor.entityID, since: window.start))))
        }
        return ComfortScore.compute(rooms: rooms, range: range, rangeOrigin: origin, window: window)
    }

    private func energyScore(now: Date, weekAgo: Date) async -> EnergyScore? {
        let meters = await electricityMeters()
        guard !meters.isEmpty else { return nil }
        // Several meters (peak and off-peak indexes) add up, hour by hour.
        var byHour: [Date: Double] = [:]
        for meter in meters {
            for point in await statistics(of: meter, since: Calendar.current.startOfDay(for: weekAgo), period: "hour") {
                if let change = point.change { byHour[point.start, default: 0] += max(0, change) }
            }
        }
        let unit = meters.lazy.compactMap { self.states[$0]?.unit }.first ?? "kWh"
        return EnergyScore.compute(hourly: byHour.map { (start: $0.key, value: $0.value) }, unit: unit, now: now)
    }

    private func networkScore(window: DateInterval, weekAgo: Date) async -> NetworkScore? {
        guard let source = internetSources else { return nil }
        let connectivity = await changes(of: source.connectivity.entityID, since: window.start)
        var today: TimeSeries?, past: TimeSeries?
        if let latency = source.latency {
            let week = await changes(of: latency.entityID, since: weekAgo)
            today = TimeSeries(changes: week.filter { $0.date >= window.start })
            past = TimeSeries(changes: week.filter { $0.date < window.start })
        }
        return NetworkScore.compute(connectivity: connectivity, latency: today, pastLatency: past, window: window)
    }
}
