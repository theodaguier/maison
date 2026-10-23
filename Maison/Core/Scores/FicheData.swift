import Foundation

// What the three fiches show besides the score: the outdoor weather and when to air, the cost of the
// electricity, the devices that used it, water, the router's throughput and its devices. Every value
// keeps its origin; nothing here is invented when a source is missing.

// MARK: - Weather and airing

/// The weather the server knows, from its first weather entity.
struct OutdoorWeather: Sendable, Equatable {
    let temperature: Double
    let humidity: Double?
    /// Home Assistant's condition ("rainy", "sunny").
    let condition: String
}

/// Whether now is a good moment to air the home, and why.
struct AiringAdvice: Sendable, Equatable {
    enum Reason: Sendable, Equatable {
        /// Indoor CO₂ above 1000 ppm in a room.
        case carbonDioxide(room: String, ppm: Double)
        /// Mild and dry outside.
        case mildOutside
    }

    let reason: Reason
    let outdoor: OutdoorWeather

    static let wetConditions: Set = ["rainy", "pouring", "snowy", "snowy-rainy", "hail", "lightning-rainy", "fog"]

    /// `nil` when airing would let rain, cold or heat in.
    static func compute(outdoor: OutdoorWeather?, carbonDioxide: [(room: String, ppm: Double)]) -> AiringAdvice? {
        guard let outdoor, !wetConditions.contains(outdoor.condition), (5...26).contains(outdoor.temperature) else { return nil }
        if let worst = carbonDioxide.max(by: { $0.ppm < $1.ppm }), worst.ppm >= 1000 {
            return AiringAdvice(reason: .carbonDioxide(room: worst.room, ppm: worst.ppm), outdoor: outdoor)
        }
        guard (12...24).contains(outdoor.temperature) else { return nil }
        return AiringAdvice(reason: .mildOutside, outdoor: outdoor)
    }
}

// MARK: - Cost

/// The price of a kWh, and where it comes from.
struct EnergyPrice: Sendable, Equatable {
    let perKilowattHour: Double
    let currency: String
    /// Set in Home Assistant's Energy dashboard or in Maison: entered either way.
    let origin: ValueOrigin
}

/// The price entered in Maison when Home Assistant has none.
enum EnergyPriceSetting {
    static let key = "energyPricePerKilowattHour"

    static func price(in defaults: UserDefaults = .standard) -> Double? {
        (defaults.object(forKey: key) as? Double).flatMap { $0 > 0 ? $0 : nil }
    }

    static func set(_ price: Double?, in defaults: UserDefaults = .standard) {
        defaults.set(price, forKey: key)
    }
}

struct EnergyCost: Sendable, Equatable {
    /// Cost of the scored day so far.
    let day: Double
    /// The month at the same pace: what is used so far this month, then the daily median for the rest.
    let monthProjection: Double?

    /// `hourly` in kWh; `day` is the score's midnight and `asOf` its last reading.
    static func compute(hourly: [(start: Date, value: Double)], price: Double, day: Date, asOf: Date, calendar: Calendar = .current) -> EnergyCost {
        let dayUse = hourly.filter { $0.start >= day && $0.start < asOf }.reduce(0) { $0 + $1.value }
        guard let month = calendar.dateInterval(of: .month, for: day) else { return EnergyCost(day: dayUse * price, monthProjection: nil) }
        let monthUse = hourly.filter { $0.start >= month.start && $0.start < asOf }.reduce(0) { $0 + $1.value }
        var daily: [Double] = []
        for back in 1...7 {
            guard let start = calendar.date(byAdding: .day, value: -back, to: day) else { continue }
            let total = hourly.filter { $0.start >= start && $0.start < start.addingTimeInterval(86_400) }.reduce(0) { $0 + $1.value }
            if total > 0 { daily.append(total) }
        }
        guard daily.count >= EnergyScore.minimumDays else { return EnergyCost(day: dayUse * price, monthProjection: nil) }
        let remaining = max(0, month.end.timeIntervalSince(asOf) / 86_400)
        return EnergyCost(day: dayUse * price, monthProjection: (monthUse + median(daily) * remaining) * price)
    }
}

// MARK: - Devices, water, network

/// One device's electricity over the scored day.
struct DeviceEnergy: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let kilowattHours: Double
}

/// What the router tells: throughput and connected devices.
struct RouterReadings: Sendable, Equatable {
    /// Download throughput over the last day, in the sensor's unit.
    var download: [(date: Date, value: Double)] = []
    var downloadUnit: String?
    var upload: Double?
    /// Devices the router sees at home right now.
    var connectedDevices: Int?

    static func == (lhs: RouterReadings, rhs: RouterReadings) -> Bool {
        lhs.download.map(\.value) == rhs.download.map(\.value) && lhs.downloadUnit == rhs.downloadUnit
            && lhs.upload == rhs.upload && lhs.connectedDevices == rhs.connectedDevices
    }
}

extension HomeStore {
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
        if isDemoHome { return EnergyPrice(perKilowattHour: 0.2516, currency: "EUR", origin: .entered) }
        if let fromServer = await serverEnergyPrice() { return EnergyPrice(perKilowattHour: fromServer, currency: currency, origin: .entered) }
        return EnergyPriceSetting.price().map { EnergyPrice(perKilowattHour: $0, currency: currency, origin: .entered) }
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
}
