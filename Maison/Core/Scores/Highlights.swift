import Foundation

// What the home screen shows under the scores: what Maison noticed in each source, most urgent first.
// Structured facts only; the wording stays in the views. Each one keeps the origin of its value and
// ends in one tap.

struct Highlight: Identifiable, Equatable, Sendable {
    let id: String
    let score: Finding.ScoreKindID
    let fact: Fact
    let origin: ValueOrigin
    let rank: Rank

    /// Lower comes first.
    enum Rank: Int, Comparable, Sendable {
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

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Fact: Equatable, Sendable {
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
struct HighlightInputs: Sendable {
    /// Climates heating at this moment.
    var heating: [String] = []
    /// Climates cooling at this moment.
    var cooling: [String] = []
    /// Whether someone is home; `nil` when nobody is tracked.
    var someoneHome: Bool?
    /// Open windows, by name, while heating or cooling runs.
    var openWindows: [String] = []
    var carbonDioxide: [(room: String, ppm: Double)] = []
    var outdoor: OutdoorWeather?
    /// The devices that used electricity on the scored day, most first.
    var devices: [DeviceEnergy] = []
    var price: EnergyPrice?
    var cost: EnergyCost?
    var connectedDevices: Int?
    var hasThermometer = false
    var meterProposalSeen = false
}

enum Highlights {
    /// A device worth naming uses at least this share of the day's electricity.
    static let minimumDeviceShare = 0.2
    /// The day is worth mentioning above this much over the habit.
    static let minimumOverHabit = 0.1
    /// Hours needed to tell what never switches off.
    static let minimumHoursForBaseline = 72

    static func compute(scores: HomeScores, inputs: HighlightInputs, calendar: Calendar = .current) -> [Highlight] {
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
            add(finding.id, .energy, .finding(finding), .estimated, .worth)
        }

        // Today
        if let room = scores.comfort?.rooms.first(where: { $0.excursion != nil }), let excursion = room.excursion {
            add("comfort:\(room.id)", .comfort, .roomOutOfRange(room: room.name, side: excursion.side, start: excursion.interval.start, percent: room.percent),
                .measured, .today)
        }
        if let energy = scores.energy, let difference = energy.difference, difference > minimumOverHabit {
            add("energy-habit", .energy, .energyAboveHabit(difference: difference, isToday: calendar.isDateInToday(energy.day)), .measured, .today)
        }
        if let energy = scores.energy, let top = inputs.devices.first {
            let total = scores.hasElectricityMeter && energy.today > 0 ? energy.today : inputs.devices.reduce(0) { $0 + $1.kilowattHours }
            let share = total > 0 ? min(1, top.kilowattHours / total) : 0
            if share >= minimumDeviceShare {
                add("top-device:\(top.id)", .energy, .topDevice(entityID: top.id, name: top.name, share: share, kilowattHours: top.kilowattHours,
                                                                isToday: calendar.isDateInToday(energy.day)), .measured, .today)
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
    static func alwaysOnWatts(_ hourly: [(start: Date, value: Double)]) -> Double? {
        let values = hourly.map(\.value).filter { $0 > 0 }
        guard values.count >= minimumHoursForBaseline else { return nil }
        return percentile(values, 0.05) * 1000
    }
}

extension HomeStore {
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
