import Foundation

/// One state an entity took, and when.
public struct StateChange: Sendable, Hashable {
    public let state: String
    public let date: Date

    public init(state: String, date: Date) {
        self.state = state
        self.date = date
    }
}

/// One period of long-term statistics (hourly or daily means kept by the recorder).
public struct StatisticPoint: Sendable, Hashable {
    public let start: Date
    public let mean: Double?
    public let min: Double?
    public let max: Double?
    /// What a total (an energy meter) grew by during the period.
    public var change: Double?
    /// The running total at the end of the period.
    public var sum: Double?

    public init(start: Date, mean: Double?, min: Double?, max: Double?, change: Double? = nil, sum: Double? = nil) {
        self.start = start
        self.mean = mean
        self.min = min
        self.max = max
        self.change = change
        self.sum = sum
    }
}

/// When a device was on during one day.
public struct DayUsage: Sendable, Equatable {
    /// On periods, clipped to the day.
    public let periods: [DateInterval]
    public let day: DateInterval

    public var total: TimeInterval { periods.reduce(0) { $0 + $1.duration } }

    /// Builds the on periods within `day` from a history whose first entry is the state at its start.
    public init(changes: [StateChange], day: DateInterval, now: Date = .now, isOn: (String) -> Bool = { $0 == "on" }) {
        self.day = day
        let end = min(day.end, now)
        var periods: [DateInterval] = []
        var onSince: Date?
        for change in changes.sorted(by: { $0.date < $1.date }) {
            // Changes after the day (yesterday's usage is read from a history that runs to now) are clamped to its end.
            let date = min(max(change.date, day.start), end)
            if isOn(change.state) {
                if onSince == nil { onSince = date }
            } else if let start = onSince {
                if date > start { periods.append(DateInterval(start: start, end: date)) }
                onSince = nil
            }
        }
        if let start = onSince, end > start {
            periods.append(DateInterval(start: start, end: end))
        }
        self.periods = periods.filter { $0.end > day.start && $0.start < end }
    }

    public init(periods: [DateInterval], day: DateInterval) {
        self.periods = periods
        self.day = day
    }
}

/// One line of an entity's logbook: what changed, and who or what changed it.
public struct LogbookEntry: Sendable, Hashable {
    public let date: Date
    public let state: String?
    /// The account behind the change, when a person did it.
    public let userID: String?
    /// The automation or script behind the change ("Dernier départ").
    public let automationName: String?

    public init(date: Date, state: String?, userID: String?, automationName: String?) {
        self.date = date
        self.state = state
        self.userID = userID
        self.automationName = automationName
    }
}

/// One run of an automation, from its stored traces.
public struct AutomationRun: Sendable, Hashable {
    public let automationID: String
    public let start: Date
    /// `finished`, `error`, `failed_conditions`, `cancelled`…
    public let execution: String

    public init(automationID: String, start: Date, execution: String) {
        self.automationID = automationID
        self.start = start
        self.execution = execution
    }

    /// Stopped by its own conditions: the rule was checked but didn't run.
    public var didRun: Bool { execution != "failed_conditions" && execution != "failed_single" }
    public var failed: Bool { execution == "error" }
}
