import Foundation

// What the home screen shows under the scores: what Maison noticed in each source, most urgent first.
// Structured facts only; the wording stays in the views. Each one keeps the origin of its value and
// ends in one tap.

public struct Highlight: Identifiable, Equatable, Sendable {
    public let id: String
    public let score: Finding.ScoreKindID
    public let fact: Fact
    public let origin: ValueOrigin
    public let rank: Rank

    public init(id: String, score: Finding.ScoreKindID, fact: Fact, origin: ValueOrigin, rank: Rank) {
        self.id = id
        self.score = score
        self.fact = fact
        self.origin = origin
        self.rank = rank
    }

    /// Lower comes first.
    public enum Rank: Int, Comparable, Sendable {
        /// To act on now.
        case now
        /// Worth money or comfort over the year.
        case worth
        /// What happened today.
        case today
        /// Context: true and useful, never urgent.
        case context
        /// A source that would let Maison say more.
        case missing

        public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Fact: Equatable, Sendable {
        case finding(Finding)
        case outage(start: Date, duration: TimeInterval)
        case roomOutOfRange(room: String, side: ComfortScore.Side, start: Date, percent: Int)
        case heatingWhileAway(entityIDs: [String])
        case coolingWhileAway(entityIDs: [String])
        case windowOpenWhileHeating(window: String, entityIDs: [String])
        case windowOpenWhileCooling(window: String, entityIDs: [String])
        case airNow(room: String, ppm: Double)
        case mildOutside(temperature: Double)
        case energyAboveHabit(difference: Double, isToday: Bool)
        case topDevice(entityID: String, name: String, share: Double, kilowattHours: Double, isToday: Bool)
        case alwaysOn(watts: Double, yearlyCost: Double?, currency: String)
        case monthCost(amount: Double, currency: String)
        case connectedDevices(count: Int)
        case missingMeter
        case missingTariff
        case missingThermometer
    }
}

/// What the home measures right now, besides the scores.
public struct HighlightInputs: Sendable {
    /// Climates heating at this moment.
    public var heating: [String] = []
    /// Climates cooling at this moment.
    public var cooling: [String] = []
    /// Whether someone is home; `nil` when nobody is tracked.
    public var someoneHome: Bool?
    /// Open windows, by name, while heating or cooling runs.
    public var openWindows: [String] = []
    public var carbonDioxide: [(room: String, ppm: Double)] = []
    public var outdoor: OutdoorWeather?
    /// The devices that used electricity on the scored day, most first.
    public var devices: [DeviceEnergy] = []
    public var price: EnergyPrice?
    public var cost: EnergyCost?
    public var connectedDevices: Int?
    public var hasThermometer = false
    public var meterProposalSeen = false

    public init(
        heating: [String] = [],
        cooling: [String] = [],
        someoneHome: Bool? = nil,
        openWindows: [String] = [],
        carbonDioxide: [(room: String, ppm: Double)] = [],
        outdoor: OutdoorWeather? = nil,
        devices: [DeviceEnergy] = [],
        price: EnergyPrice? = nil,
        cost: EnergyCost? = nil,
        connectedDevices: Int? = nil,
        hasThermometer: Bool = false,
        meterProposalSeen: Bool = false
    ) {
        self.heating = heating
        self.cooling = cooling
        self.someoneHome = someoneHome
        self.openWindows = openWindows
        self.carbonDioxide = carbonDioxide
        self.outdoor = outdoor
        self.devices = devices
        self.price = price
        self.cost = cost
        self.connectedDevices = connectedDevices
        self.hasThermometer = hasThermometer
        self.meterProposalSeen = meterProposalSeen
    }
}

public enum Highlights {
    /// A device worth naming uses at least this share of the day's electricity.
    public static let minimumDeviceShare = 0.2
    /// The day is worth mentioning above this much over the habit.
    public static let minimumOverHabit = 0.1
    /// Hours needed to tell what never switches off.
    public static let minimumHoursForBaseline = 72

    /// `now` tells whether the scored day is today or yesterday.
    public static func compute(scores: HomeScores, inputs: HighlightInputs, now: Date, calendar: Calendar = .current) -> [Highlight] {
        var result: [Highlight] = []
        func add(_ id: String, _ score: Finding.ScoreKindID, _ fact: Highlight.Fact, _ origin: ValueOrigin, _ rank: Highlight.Rank) {
            result.append(Highlight(id: id, score: score, fact: fact, origin: origin, rank: rank))
        }

        // Now
        if !inputs.heating.isEmpty, inputs.someoneHome == false {
            add("heating-away", .comfort, .heatingWhileAway(entityIDs: inputs.heating), .measured, .now)
        }
        if !inputs.cooling.isEmpty, inputs.someoneHome == false {
            add("cooling-away", .comfort, .coolingWhileAway(entityIDs: inputs.cooling), .measured, .now)
        }
        if let window = inputs.openWindows.first {
            if !inputs.heating.isEmpty {
                add("window-heating", .comfort, .windowOpenWhileHeating(window: window, entityIDs: inputs.heating), .measured, .now)
            } else if !inputs.cooling.isEmpty {
                add("window-cooling", .comfort, .windowOpenWhileCooling(window: window, entityIDs: inputs.cooling), .measured, .now)
            }
        }
        let airing = AiringAdvice.compute(outdoor: inputs.outdoor, carbonDioxide: inputs.carbonDioxide)
        if case .carbonDioxide(let room, let ppm)? = airing?.reason {
            add("air:\(room)", .comfort, .airNow(room: room, ppm: ppm), .measured, .now)
        }
        if let outage = scores.network?.outages.max(by: { $0.duration < $1.duration }) {
            add("outage:\(Int(outage.start.timeIntervalSince1970))", .network, .outage(start: outage.start, duration: outage.duration), .measured, .now)
        }

        // Worth it
        for finding in scores.findings {
            add(finding.id, finding.score, .finding(finding), finding.yearlyValueOrigin, .worth)
        }

        // Today
        if let room = scores.comfort?.rooms.first(where: { $0.excursion != nil }), let excursion = room.excursion {
            add("comfort:\(room.id)", .comfort, .roomOutOfRange(room: room.name, side: excursion.side, start: excursion.interval.start, percent: room.percent),
                .measured, .today)
        }
        if let energy = scores.energy, let difference = energy.difference, difference > minimumOverHabit {
            add("energy-habit", .energy, .energyAboveHabit(difference: difference, isToday: calendar.isDate(energy.day, inSameDayAs: now)), .measured, .today)
        }
        if let energy = scores.energy, let top = inputs.devices.first {
            let total = scores.hasElectricityMeter && energy.today > 0 ? energy.today : inputs.devices.reduce(0) { $0 + $1.kilowattHours }
            let share = total > 0 ? min(1, top.kilowattHours / total) : 0
            if share >= minimumDeviceShare {
                add("top-device:\(top.id)", .energy, .topDevice(entityID: top.id, name: top.name, share: share, kilowattHours: top.kilowattHours,
                                                                isToday: calendar.isDate(energy.day, inSameDayAs: now)), .measured, .today)
            }
        }

        // Context
        if let energy = scores.energy, scores.hasElectricityMeter, let watts = alwaysOnWatts(energy.history) {
            let yearly = inputs.price.map { watts / 1000 * 24 * 365 * $0.perKilowattHour }
            add("always-on", .energy, .alwaysOn(watts: watts, yearlyCost: yearly, currency: inputs.price?.currency ?? ""),
                .estimated, .context)
        }
        if let projection = inputs.cost?.monthProjection, let price = inputs.price {
            add("month-cost", .energy, .monthCost(amount: projection, currency: price.currency), .estimated, .context)
        }
        if case .mildOutside? = airing?.reason, let outdoor = inputs.outdoor {
            add("air-mild", .comfort, .mildOutside(temperature: outdoor.temperature), .measured, .context)
        }
        if let count = inputs.connectedDevices, count > 0 {
            add("connected-devices", .network, .connectedDevices(count: count), .measured, .context)
        }

        // One missing source at most, the one that brings the most.
        if !scores.hasElectricityMeter {
            if !inputs.meterProposalSeen { add("missing-meter", .energy, .missingMeter, .measured, .missing) }
        } else if inputs.price == nil {
            add("missing-tariff", .energy, .missingTariff, .entered, .missing)
        } else if !inputs.hasThermometer {
            add("missing-thermometer", .comfort, .missingThermometer, .measured, .missing)
        }

        // Stable: the order they were added in breaks ties.
        return result.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
    }

    /// What the home draws when everything is off: the lowest hours of the week, in watts. `nil` with
    /// fewer than three days of hourly readings.
    public static func alwaysOnWatts(_ hourly: [(start: Date, value: Double)]) -> Double? {
        let values = hourly.map(\.value).filter { $0 > 0 }
        guard values.count >= minimumHoursForBaseline else { return nil }
        return percentile(values, 0.05) * 1000
    }
}
