import Foundation

// The three V1 scores. Pure computation on measured values: no SwiftUI, no Home Assistant types beyond
// `StateChange`, so the same code can run in the add-on later. Wording stays in the views.

/// Where a value comes from. Every number Maison shows carries one.
enum ValueOrigin: String, Sendable, Hashable, Codable {
    case measured
    case estimated
    case entered
}

/// One series of values over time, as a sensor reported them.
struct TimeSeries: Sendable, Equatable {
    var changes: [StateChange]

    /// Each value with the interval it held, clipped to `window`. Unreadable states (unavailable) leave gaps.
    func segments(in window: DateInterval) -> [(value: Double, interval: DateInterval)] {
        let sorted = changes.sorted { $0.date < $1.date }
        var result: [(Double, DateInterval)] = []
        for (index, change) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].date : window.end
            let start = max(change.date, window.start), end = min(next, window.end)
            guard end > start, let value = Double(change.state) else { continue }
            result.append((value, DateInterval(start: start, end: end)))
        }
        return result
    }
}

// MARK: - Comfort

/// The share of the day each room spent inside the household's temperature range.
struct ComfortScore: Sendable, Equatable {
    struct Room: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let percent: Int
        /// The longest stretch outside the range, if any lasted 15 minutes or more.
        let excursion: Excursion?
        /// The readings over the window, oldest first, for the room's small chart.
        var readings: [(date: Date, value: Double)] = []

        static func == (lhs: Room, rhs: Room) -> Bool {
            lhs.id == rhs.id && lhs.percent == rhs.percent && lhs.excursion == rhs.excursion
                && lhs.readings.map(\.date) == rhs.readings.map(\.date) && lhs.readings.map(\.value) == rhs.readings.map(\.value)
        }

        /// The reading closest to the middle of the excursion, if any.
        var excursionValue: Double? {
            guard let excursion else { return nil }
            let middle = excursion.interval.start.addingTimeInterval(excursion.interval.duration / 2)
            return readings.min { abs($0.date.timeIntervalSince(middle)) < abs($1.date.timeIntervalSince(middle)) }?.value
        }
    }

    enum Side: Sendable, Equatable { case tooWarm, tooCold }

    struct Excursion: Sendable, Equatable {
        let side: Side
        let interval: DateInterval
    }

    let percent: Int
    /// Worst room first.
    let rooms: [Room]
    let range: ClosedRange<Double>
    let rangeOrigin: ValueOrigin
    /// The range is the usual one Maison starts from, not yet learned from the household's readings.
    var rangeIsStarting = false

    static let minimumExcursion: TimeInterval = 15 * 60

    /// `nil` when no room has a reading in the window.
    static func compute(
        rooms: [(id: String, name: String, series: TimeSeries)],
        range: ClosedRange<Double>,
        rangeOrigin: ValueOrigin,
        window: DateInterval
    ) -> ComfortScore? {
        var inside: TimeInterval = 0, covered: TimeInterval = 0
        var scored: [Room] = []
        for room in rooms {
            let segments = room.series.segments(in: window)
            let roomCovered = segments.reduce(0) { $0 + $1.interval.duration }
            guard roomCovered > 0 else { continue }
            let roomInside = segments.filter { range.contains($0.value) }.reduce(0) { $0 + $1.interval.duration }
            inside += roomInside
            covered += roomCovered
            scored.append(Room(
                id: room.id,
                name: room.name,
                percent: Int((100 * roomInside / roomCovered).rounded()),
                excursion: longestExcursion(segments, range: range),
                readings: segments.map { (date: $0.interval.start, value: $0.value) }
            ))
        }
        guard covered > 0 else { return nil }
        return ComfortScore(
            percent: Int((100 * inside / covered).rounded()),
            rooms: scored.sorted { $0.percent < $1.percent || ($0.percent == $1.percent && $0.name < $1.name) },
            range: range,
            rangeOrigin: rangeOrigin
        )
    }

    private static func longestExcursion(_ segments: [(value: Double, interval: DateInterval)], range: ClosedRange<Double>) -> Excursion? {
        var best: Excursion?
        var current: (side: Side, start: Date, end: Date)?
        func close() {
            if let run = current, run.end.timeIntervalSince(run.start) >= minimumExcursion,
               run.end.timeIntervalSince(run.start) > (best?.interval.duration ?? 0) {
                best = Excursion(side: run.side, interval: DateInterval(start: run.start, end: run.end))
            }
            current = nil
        }
        for segment in segments {
            let side: Side? = segment.value > range.upperBound ? .tooWarm : segment.value < range.lowerBound ? .tooCold : nil
            if let side, let run = current, run.side == side, run.end >= segment.interval.start {
                current = (side, run.start, segment.interval.end)
            } else {
                close()
                if let side { current = (side, segment.interval.start, segment.interval.end) }
            }
        }
        close()
        return best
    }
}

// MARK: - Energy

/// Today's electricity compared with the household's own habit at the same time of day.
struct EnergyScore: Sendable, Equatable {
    /// Energy used on `day`, from midnight to `asOf`, in `unit`.
    let today: Double
    /// The midnight the score is about: today with a live meter, yesterday with readings from the grid operator.
    var day: Date = .distantPast
    /// The end of the last hour with a reading.
    var asOf: Date = .distantPast
    /// The median of the previous days at the same time; `nil` until there are three of them.
    let usual: Double?
    let unit: String
    /// The last 24 hours, oldest first, each hour's energy in `unit`.
    let lastDay: [(start: Date, value: Double)]
    /// Every hour read, for the cost of the month.
    var history: [(start: Date, value: Double)] = []
    /// The meters counted.
    var meterIDs: [String] = []
    /// Whether the meters are the ones set in Home Assistant's Energy dashboard; otherwise Maison picked
    /// the energy total that used the most, and suggests it.
    var meterIsConfirmed = true

    /// `nil` while there is no habit to compare with.
    var percent: Int? {
        guard let usual, usual > 0 else { return nil }
        return Self.percent(ratio: today / usual)
    }

    /// −0.18 is 18 % under the habit.
    var difference: Double? {
        guard let usual, usual > 0 else { return nil }
        return today / usual - 1
    }

    /// Energy used the day before, from midnight to the same time; `nil` without a reading that day.
    var dayBeforeAtThisTime: Double? {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { return nil }
        let hours = history.filter { $0.start >= previous && $0.start < previous.addingTimeInterval(86_400) }
        guard !hours.isEmpty else { return nil }
        let end = previous.addingTimeInterval(asOf.timeIntervalSince(day))
        return hours.filter { $0.start < end }.reduce(0) { $0 + $1.value }
    }

    /// 100 at 30 % under the habit or less, 50 at the habit, 0 at 50 % over it.
    static func percent(ratio: Double) -> Int {
        let score = ratio <= 1 ? 100 - (ratio - 0.7) / 0.3 * 50 : 50 - (ratio - 1) / 0.5 * 50
        return Int(min(100, max(0, score)).rounded())
    }

    static let minimumDays = 3

    /// `hourly` is the energy used each hour (the statistics' `change`), over the last eight days or more.
    /// The score stops at the last hour with a reading: a meter read the next day scores yesterday, whole.
    static func compute(hourly: [(start: Date, value: Double)], unit: String, now: Date, calendar: Calendar = .current) -> EnergyScore? {
        guard let latest = hourly.map(\.start).max() else { return nil }
        let asOf = min(now, latest.addingTimeInterval(3600))
        let midnight = calendar.startOfDay(for: asOf.addingTimeInterval(-1))
        let elapsed = asOf.timeIntervalSince(midnight)
        func used(from start: Date, to end: Date) -> Double {
            hourly.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.value }
        }
        let today = used(from: midnight, to: asOf)
        var previous: [Double] = []
        for back in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: midnight),
                  hourly.contains(where: { $0.start >= day && $0.start < day.addingTimeInterval(86_400) }) else { continue }
            previous.append(used(from: day, to: day.addingTimeInterval(elapsed)))
        }
        let usual = previous.count >= minimumDays ? median(previous) : nil
        let lastDay = hourly.filter { $0.start >= asOf.addingTimeInterval(-86_400) && $0.start < asOf }.sorted { $0.start < $1.start }
        return EnergyScore(today: today, day: midnight, asOf: asOf, usual: usual, unit: unit, lastDay: lastDay, history: hourly)
    }

    static func == (lhs: EnergyScore, rhs: EnergyScore) -> Bool {
        lhs.today == rhs.today && lhs.day == rhs.day && lhs.asOf == rhs.asOf && lhs.usual == rhs.usual && lhs.unit == rhs.unit
            && lhs.lastDay.map(\.start) == rhs.lastDay.map(\.start) && lhs.lastDay.map(\.value) == rhs.lastDay.map(\.value)
    }
}

// MARK: - Network

/// Whether the internet was there today, and how fast it answered compared with the household's habit.
struct NetworkScore: Sendable, Equatable {
    /// Share of the day the connection was up, from 0 to 1.
    let availability: Double
    /// Interruptions of a minute or more.
    let outages: [DateInterval]
    /// Round-trip times today, in milliseconds.
    let latency: [(date: Date, milliseconds: Double)]
    /// The 10th to 90th percentile of the previous days; `nil` without enough history.
    let usualLatency: ClosedRange<Double>?

    /// Availability weighs 60 %, answering within the habit 40 %; without a habit, availability alone.
    var percent: Int {
        guard let usualLatency, !latency.isEmpty else { return Int((100 * availability).rounded()) }
        let within = Double(latency.filter { $0.milliseconds <= usualLatency.upperBound }.count) / Double(latency.count)
        return Int((100 * (0.6 * availability + 0.4 * within)).rounded())
    }

    static let minimumOutage: TimeInterval = 60

    /// `connectivity` is an on/off sensor; `latency` today's round trips; `pastLatency` the previous days'.
    static func compute(connectivity: [StateChange], latency: TimeSeries?, pastLatency: TimeSeries?, window: DateInterval) -> NetworkScore? {
        let sorted = connectivity.sorted { $0.date < $1.date }
        var up: TimeInterval = 0, known: TimeInterval = 0
        var outages: [DateInterval] = []
        for (index, change) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].date : window.end
            let start = max(change.date, window.start), end = min(next, window.end)
            guard end > start, change.state == "on" || change.state == "off" else { continue }
            known += end.timeIntervalSince(start)
            if change.state == "on" {
                up += end.timeIntervalSince(start)
            } else if end.timeIntervalSince(start) >= minimumOutage {
                outages.append(DateInterval(start: start, end: end))
            }
        }
        guard known > 0 else { return nil }
        let today = latency?.segments(in: window).map { (date: $0.interval.start, milliseconds: $0.value) } ?? []
        let past = (pastLatency?.changes ?? []).compactMap { Double($0.state) }
        return NetworkScore(
            availability: up / known,
            outages: outages,
            latency: today,
            usualLatency: past.count >= 24 ? percentile(past, 0.1)...percentile(past, 0.9) : nil
        )
    }

    static func == (lhs: NetworkScore, rhs: NetworkScore) -> Bool {
        lhs.availability == rhs.availability && lhs.outages == rhs.outages && lhs.usualLatency == rhs.usualLatency
            && lhs.latency.map(\.date) == rhs.latency.map(\.date) && lhs.latency.map(\.milliseconds) == rhs.latency.map(\.milliseconds)
    }
}

// MARK: - Helpers

func median(_ values: [Double]) -> Double {
    percentile(values, 0.5)
}

/// Linear interpolation between the closest ranks.
func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let rank = p * Double(sorted.count - 1)
    let low = Int(rank.rounded(.down)), high = Int(rank.rounded(.up))
    return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
}
