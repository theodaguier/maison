import Foundation

// Findings: something Maison noticed, why it thinks so, what it is worth. Structured facts only: the
// code computes every value and tags its origin; the app words them and builds the rule that fixes it.

// MARK: - Tariff

/// The household's electricity tariff, as entered: one price, or peak and off-peak hours.
public struct EnergyTariff: Codable, Equatable, Sendable {
    /// Base price, or the peak price with off-peak hours.
    public var price: Double
    public var offPeak: OffPeak?

    public init(price: Double, offPeak: OffPeak? = nil) {
        self.price = price
        self.offPeak = offPeak
    }

    public struct OffPeak: Codable, Equatable, Sendable {
        public var price: Double
        /// Hours of the day, 0 to 23: off-peak from `startHour` to `endHour`, across midnight when needed.
        public var startHour: Int
        public var endHour: Int

        public init(price: Double, startHour: Int, endHour: Int) {
            self.price = price
            self.startHour = startHour
            self.endHour = endHour
        }

        public func contains(hour: Int) -> Bool {
            startHour <= endHour ? (startHour..<endHour).contains(hour) : hour >= startHour || hour < endHour
        }

        /// Off-peak hours in a day.
        public var duration: Int { startHour <= endHour ? endHour - startHour : 24 - startHour + endHour }
    }

    /// The price of a kWh used during `hour`.
    public func price(atHour hour: Int) -> Double {
        if let offPeak, offPeak.contains(hour: hour) { return offPeak.price }
        return price
    }
}

// MARK: - Findings

public struct Finding: Identifiable, Equatable, Sendable {
    /// Stable across refreshes, so ignoring one sticks.
    public let id: String
    /// What Maison noticed.
    public let kind: Kind
    /// The score it belongs to.
    public let score: ScoreKindID
    /// The device it is about, and the name it goes by in the home.
    public let deviceID: String
    public let deviceName: String
    /// The switch that powers the device; `nil` when nothing in the home can switch it.
    public let switchEntityID: String?
    /// What fixing it is worth each year, in `currency`: estimated from the tariff.
    public let yearlyValue: Double
    public let currency: String
    /// Why Maison thinks so, each with the origin of its values.
    public let reasons: [Reason]
    /// The device's use over the day the finding is about, by hour, for its timeline: measured.
    public let usage: [Int: Double]
    /// The off-peak hours of the tariff: entered.
    public let offPeak: EnergyTariff.OffPeak?

    public init(
        id: String,
        kind: Kind,
        score: ScoreKindID,
        deviceID: String,
        deviceName: String,
        switchEntityID: String?,
        yearlyValue: Double,
        currency: String,
        reasons: [Reason],
        usage: [Int: Double],
        offPeak: EnergyTariff.OffPeak?
    ) {
        self.id = id
        self.kind = kind
        self.score = score
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.switchEntityID = switchEntityID
        self.yearlyValue = yearlyValue
        self.currency = currency
        self.reasons = reasons
        self.usage = usage
        self.offPeak = offPeak
    }

    /// Where `yearlyValue` comes from.
    public var yearlyValueOrigin: ValueOrigin { .estimated }

    public enum Kind: String, Sendable {
        /// A device that runs in peak hours when off-peak hours exist.
        case peakHours
    }

    public enum ScoreKindID: String, Sendable { case comfort, energy, network }

    public enum Reason: Equatable, Sendable {
        /// The hour the device used the most, and the share of its day in peak hours.
        case busiestHour(hour: Int, peakShare: Double)
        /// The off-peak hours of the tariff.
        case offPeakHours(startHour: Int, endHour: Int)
        /// What running in peak hours costs each day, and the kWh used at the peak price.
        case extraCost(perDay: Double, currency: String, peakKilowattHours: Double)

        public var origin: ValueOrigin {
            switch self {
            case .busiestHour: .measured
            case .offPeakHours: .entered
            case .extraCost: .estimated
            }
        }
    }
}

public enum PeakHoursFinding {
    /// A device used at least this much in a day is worth moving.
    public static let minimumDailyUse = 0.5
    /// And at least this share of it fell in peak hours.
    public static let minimumPeakShare = 0.6

    /// A device that runs in peak hours when off-peak hours exist. `usage` is its kWh by hour of one day.
    public static func compute(
        deviceID: String,
        deviceName: String,
        usage: [Int: Double],
        tariff: EnergyTariff,
        currency: String,
        switchEntity: String?
    ) -> Finding? {
        guard let offPeak = tariff.offPeak, offPeak.price < tariff.price else { return nil }
        let total = usage.values.reduce(0, +)
        let peak = usage.filter { !offPeak.contains(hour: $0.key) }.values.reduce(0, +)
        guard total >= minimumDailyUse, peak / total >= minimumPeakShare else { return nil }
        let extraPerDay = peak * (tariff.price - offPeak.price)
        let busiest = usage.max { $0.value < $1.value }?.key ?? 0

        return Finding(
            id: "peak-hours:\(deviceID)",
            kind: .peakHours,
            score: .energy,
            deviceID: deviceID,
            deviceName: deviceName,
            switchEntityID: switchEntity,
            yearlyValue: extraPerDay * 365,
            currency: currency,
            reasons: [
                .busiestHour(hour: busiest, peakShare: peak / total),
                .offPeakHours(startHour: offPeak.startHour, endHour: offPeak.endHour),
                .extraCost(perDay: extraPerDay, currency: currency, peakKilowattHours: peak),
            ],
            usage: usage,
            offPeak: offPeak
        )
    }
}
