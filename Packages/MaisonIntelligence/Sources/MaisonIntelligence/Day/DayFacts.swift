import Foundation

// What stood out today, computed from the home's history. Structured facts only: the app words them,
// and the on-device model rewords that wording without adding a number.

/// One notable thing about the day.
public enum DayFact: Identifiable, Hashable, Sendable {
    /// The warmest hour across indoor thermometers, in the home's temperature unit.
    case temperaturePeak(entityID: String, room: String?, degrees: Double, hour: Date, versusYesterday: DayChange?)
    /// A heater or air conditioner that ran today.
    case climateRun(entityID: String, name: String, room: String?, duration: TimeInterval, target: Double?, heating: Bool)
    /// The last time a lock was locked or unlocked today.
    case lock(entityID: String, name: String, locked: Bool, at: Date, by: DayActor?)
    /// Today's energy use, with the change in percent from yesterday at the same time.
    case energyUse(amount: Double, unit: String, versusYesterday: DayChange?)
    /// An automation that ran today, and how many times.
    case automationRuns(name: String, count: Int)

    public var id: String {
        switch self {
        case .temperaturePeak: "temperature"
        case .climateRun(let entityID, _, _, _, _, _): "climate.\(entityID)"
        case .lock(let entityID, _, _, _, _): "lock.\(entityID)"
        case .energyUse: "energy"
        case .automationRuns(let name, _): "automation.\(name)"
        }
    }
}

/// How a value compares with yesterday's. The magnitude is positive, in the fact's own unit.
public enum DayChange: Hashable, Sendable {
    case same
    case more(Double)
    case less(Double)
}

/// Who or what changed a device.
public enum DayActor: Hashable, Sendable {
    case automation(String)
    case person(String)
}

/// What the day's facts are computed from: the history the source already read.
public struct DayInputs: Sendable {
    public struct Thermometer: Sendable {
        public let entityID: String
        public let room: String?
        /// Hourly statistics since the start of yesterday.
        public let points: [StatisticPoint]

        public init(entityID: String, room: String?, points: [StatisticPoint]) {
            self.entityID = entityID
            self.room = room
            self.points = points
        }
    }

    public struct Climate: Sendable {
        public let entityID: String
        public let name: String
        public let room: String?
        public let target: Double?
        /// Today's states, the first one being the state at midnight.
        public let changes: [StateChange]

        public init(entityID: String, name: String, room: String?, target: Double?, changes: [StateChange]) {
            self.entityID = entityID
            self.name = name
            self.room = room
            self.target = target
            self.changes = changes
        }
    }

    public struct Lock: Sendable {
        public let entityID: String
        public let name: String
        public let entries: [LogbookEntry]

        public init(entityID: String, name: String, entries: [LogbookEntry]) {
            self.entityID = entityID
            self.name = name
            self.entries = entries
        }
    }

    public var thermometers: [Thermometer]
    public var climates: [Climate]
    public var locks: [Lock]
    /// The Energy score, read for today.
    public var energy: EnergyScore?
    public var automationRuns: [AutomationRun]
    /// Automation names by id.
    public var automationNames: [String: String]
    /// People's names by account.
    public var people: [String: String]

    public init(
        thermometers: [Thermometer] = [],
        climates: [Climate] = [],
        locks: [Lock] = [],
        energy: EnergyScore? = nil,
        automationRuns: [AutomationRun] = [],
        automationNames: [String: String] = [:],
        people: [String: String] = [:]
    ) {
        self.thermometers = thermometers
        self.climates = climates
        self.locks = locks
        self.energy = energy
        self.automationRuns = automationRuns
        self.automationNames = automationNames
        self.people = people
    }
}

public enum DayFacts {
    /// What stood out during `day`, in the order the summary lists it.
    public static func compute(_ inputs: DayInputs, day: DateInterval, now: Date) -> [DayFact] {
        var facts: [DayFact] = []
        if let peak = temperaturePeak(inputs.thermometers, day: day) { facts.append(peak) }
        facts += climateRuns(inputs.climates, day: day, now: now)
        facts += lockEvents(inputs.locks, day: day, people: inputs.people)
        if let energy = energyUse(inputs.energy, day: day) { facts.append(energy) }
        facts += automationRuns(inputs.automationRuns, names: inputs.automationNames, day: day)
        return facts
    }

    /// The warmest hour of the day across indoor thermometers, compared with yesterday's warmest.
    static func temperaturePeak(_ thermometers: [DayInputs.Thermometer], day: DateInterval) -> DayFact? {
        var peak: (thermometer: DayInputs.Thermometer, value: Double, hour: Date)?
        var yesterdayPeak: Double?
        for thermometer in thermometers {
            for point in thermometer.points {
                guard let value = point.max ?? point.mean else { continue }
                if point.start < day.start {
                    yesterdayPeak = max(yesterdayPeak ?? value, value)
                } else if value > (peak?.value ?? -.infinity) {
                    peak = (thermometer, value, point.start)
                }
            }
        }
        guard let peak else { return nil }
        let change: DayChange? = yesterdayPeak.map { yesterday in
            let difference = peak.value - yesterday
            if abs(difference) < 0.3 { return .same }
            return difference > 0 ? .more(abs(difference)) : .less(abs(difference))
        }
        return .temperaturePeak(
            entityID: peak.thermometer.entityID,
            room: peak.thermometer.room,
            degrees: peak.value,
            hour: peak.hour,
            versusYesterday: change
        )
    }

    /// How long each heater or air conditioner ran, when it ran five minutes or more.
    static func climateRuns(_ climates: [DayInputs.Climate], day: DateInterval, now: Date) -> [DayFact] {
        climates.compactMap { climate in
            let usage = DayUsage(changes: climate.changes, day: day, now: now) { !["off", "unavailable", "unknown"].contains($0) }
            guard usage.total >= 5 * 60 else { return nil }
            return .climateRun(
                entityID: climate.entityID,
                name: climate.name,
                room: climate.room,
                duration: usage.total,
                target: climate.target,
                heating: climate.changes.contains { $0.state == "heat" }
            )
        }
    }

    /// The last time each lock was locked or unlocked during the day, and by whom.
    static func lockEvents(_ locks: [DayInputs.Lock], day: DateInterval, people: [String: String]) -> [DayFact] {
        locks.compactMap { lock in
            guard let last = lock.entries.last(where: { $0.date >= day.start && ["locked", "unlocked"].contains($0.state ?? "") }) else {
                return nil
            }
            let actor: DayActor? = if let automation = last.automationName {
                .automation(automation)
            } else if let person = last.userID.flatMap({ people[$0] }) {
                .person(person)
            } else {
                nil
            }
            return .lock(entityID: lock.entityID, name: lock.name, locked: last.state == "locked", at: last.date, by: actor)
        }
    }

    /// Today's energy use compared with the same time yesterday. Nothing when the score is about another day,
    /// as with a meter read the next day.
    static func energyUse(_ energy: EnergyScore?, day: DateInterval) -> DayFact? {
        guard let energy, energy.day == day.start else { return nil }
        guard let yesterday = energy.dayBeforeAtThisTime, yesterday > 0 else {
            return .energyUse(amount: energy.today, unit: energy.unit, versusYesterday: nil)
        }
        let difference = energy.today - yesterday
        let percent = (abs(difference) / yesterday * 100).rounded()
        let change: DayChange = if percent == 0 { .same } else if difference < 0 { .less(percent) } else { .more(percent) }
        return .energyUse(amount: energy.today, unit: energy.unit, versusYesterday: change)
    }

    /// The automations that ran during the day, busiest first, at most three: one fact per rule,
    /// since "4 automation runs" reads as four automations.
    static func automationRuns(_ runs: [AutomationRun], names: [String: String], day: DateInterval) -> [DayFact] {
        var counts: [(name: String, runs: Int)] = []
        for run in runs.filter({ $0.didRun && day.contains($0.start) }).sorted(by: { $0.start < $1.start }) {
            let name = names[run.automationID] ?? run.automationID
            if let index = counts.firstIndex(where: { $0.name == name }) {
                counts[index].runs += 1
            } else {
                counts.append((name, 1))
            }
        }
        return counts.sorted { $0.runs > $1.runs }.prefix(3).map { .automationRuns(name: $0.name, count: $0.runs) }
    }
}
