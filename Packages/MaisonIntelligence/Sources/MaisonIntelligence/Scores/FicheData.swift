import Foundation

// What the three fiches show besides the score: the outdoor weather and when to air, the cost of the
// electricity, the devices that used it, the router's throughput and its devices. Every value keeps its
// origin; nothing here is invented when a source is missing.

// MARK: - Weather and airing

/// The weather the server knows, from its first weather entity.
public struct OutdoorWeather: Sendable, Equatable {
    public let temperature: Double
    public let humidity: Double?
    /// The source's condition ("rainy", "sunny").
    public let condition: String

    public init(temperature: Double, humidity: Double?, condition: String) {
        self.temperature = temperature
        self.humidity = humidity
        self.condition = condition
    }
}

/// Whether now is a good moment to air the home, and why.
public struct AiringAdvice: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// Indoor CO₂ above 1000 ppm in a room.
        case carbonDioxide(room: String, ppm: Double)
        /// Mild and dry outside.
        case mildOutside
    }

    public let reason: Reason
    public let outdoor: OutdoorWeather

    public init(reason: Reason, outdoor: OutdoorWeather) {
        self.reason = reason
        self.outdoor = outdoor
    }

    public static let wetConditions: Set = ["rainy", "pouring", "snowy", "snowy-rainy", "hail", "lightning-rainy", "fog"]

    /// `nil` when airing would let rain, cold or heat in.
    public static func compute(outdoor: OutdoorWeather?, carbonDioxide: [(room: String, ppm: Double)]) -> AiringAdvice? {
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
public struct EnergyPrice: Sendable, Equatable {
    public let perKilowattHour: Double
    public let currency: String
    /// Set in the source's energy settings or in Maison: entered either way.
    public let origin: ValueOrigin
    /// The tariff entered in Maison, with its off-peak hours.
    public var tariff: EnergyTariff?

    public init(perKilowattHour: Double, currency: String, origin: ValueOrigin, tariff: EnergyTariff? = nil) {
        self.perKilowattHour = perKilowattHour
        self.currency = currency
        self.origin = origin
        self.tariff = tariff
    }

    /// The price of a kWh used during `hour`.
    public func price(atHour hour: Int) -> Double {
        tariff?.price(atHour: hour) ?? perKilowattHour
    }
}

public struct EnergyCost: Sendable, Equatable {
    /// Cost of the scored day so far.
    public let day: Double
    /// The month at the same pace: what is used so far this month, then the daily median for the rest.
    public let monthProjection: Double?

    public init(day: Double, monthProjection: Double?) {
        self.day = day
        self.monthProjection = monthProjection
    }

    /// `hourly` in kWh; `day` is the score's midnight and `asOf` its last reading.
    public static func compute(hourly: [(start: Date, value: Double)], price: Double, day: Date, asOf: Date, calendar: Calendar = .current) -> EnergyCost {
        compute(hourly: hourly, price: { _ in price }, day: day, asOf: asOf, calendar: calendar)
    }

    /// With a price that depends on the hour (off-peak hours).
    public static func compute(hourly: [(start: Date, value: Double)], price: (Int) -> Double, day: Date, asOf: Date, calendar: Calendar = .current) -> EnergyCost {
        func cost(from start: Date, to end: Date) -> Double {
            hourly.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.value * price(calendar.component(.hour, from: $1.start)) }
        }
        let dayCost = cost(from: day, to: asOf)
        guard let month = calendar.dateInterval(of: .month, for: day) else { return EnergyCost(day: dayCost, monthProjection: nil) }
        var daily: [Double] = []
        for back in 1...7 {
            guard let start = calendar.date(byAdding: .day, value: -back, to: day) else { continue }
            let total = cost(from: start, to: start.addingTimeInterval(86_400))
            if total > 0 { daily.append(total) }
        }
        guard daily.count >= EnergyScore.minimumDays else { return EnergyCost(day: dayCost, monthProjection: nil) }
        let remaining = max(0, month.end.timeIntervalSince(asOf) / 86_400)
        return EnergyCost(day: dayCost, monthProjection: cost(from: month.start, to: asOf) + median(daily) * remaining)
    }
}

// MARK: - Devices, network

/// One device's electricity over the scored day.
public struct DeviceEnergy: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kilowattHours: Double

    public init(id: String, name: String, kilowattHours: Double) {
        self.id = id
        self.name = name
        self.kilowattHours = kilowattHours
    }
}

/// What the router tells: throughput and connected devices.
public struct RouterReadings: Sendable, Equatable {
    /// Download throughput over the last day, in the sensor's unit.
    public var download: [(date: Date, value: Double)]
    public var downloadUnit: String?
    public var upload: Double?
    /// Devices the router sees at home right now.
    public var connectedDevices: Int?

    public init(download: [(date: Date, value: Double)] = [], downloadUnit: String? = nil, upload: Double? = nil, connectedDevices: Int? = nil) {
        self.download = download
        self.downloadUnit = downloadUnit
        self.upload = upload
        self.connectedDevices = connectedDevices
    }

    public static func == (lhs: RouterReadings, rhs: RouterReadings) -> Bool {
        lhs.download.map(\.value) == rhs.download.map(\.value) && lhs.downloadUnit == rhs.downloadUnit
            && lhs.upload == rhs.upload && lhs.connectedDevices == rhs.connectedDevices
    }
}
