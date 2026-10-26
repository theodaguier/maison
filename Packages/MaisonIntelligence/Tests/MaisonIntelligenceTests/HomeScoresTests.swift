import Foundation
@testable import MaisonIntelligence
import Testing

struct HomeScoresTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var window: DateInterval { DateInterval(start: start, duration: 86_400) }

    private func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    // MARK: Comfort

    @Test func comfortCountsTheTimeEachRoomSpendsInTheRange() throws {
        let living = TimeSeries(changes: [StateChange(state: "21", date: start)])
        let bedroom = TimeSeries(changes: [
            StateChange(state: "21", date: start),
            StateChange(state: "24.5", date: at(1)),
            StateChange(state: "21.5", date: at(3)),
        ])
        let score = try #require(ComfortScore.compute(
            rooms: [("living", "Salon", living), ("bedroom", "Chambre", bedroom)],
            range: 20...22,
            rangeOrigin: .entered,
            window: window
        ))

        #expect(score.percent == 96)
        #expect(score.rooms.map(\.name) == ["Chambre", "Salon"])
        #expect(score.rooms.map(\.percent) == [92, 100])
        let excursion = try #require(score.rooms[0].excursion)
        #expect(excursion.side == .tooWarm)
        #expect(excursion.interval == DateInterval(start: at(1), end: at(3)))
        #expect(score.rooms[1].excursion == nil)
    }

    @Test func aShortExcursionIsNotWorthMentioning() throws {
        let series = TimeSeries(changes: [
            StateChange(state: "21", date: start),
            StateChange(state: "19", date: at(5)),
            StateChange(state: "21", date: at(5.2)),
        ])
        let score = try #require(ComfortScore.compute(rooms: [("r", "Bureau", series)], range: 20...22, rangeOrigin: .entered, window: window))
        #expect(score.rooms[0].excursion == nil)
        #expect(score.rooms[0].percent == 99)
    }

    @Test func unreadableStatesLeaveGapsInsteadOfCountingAsOutside() throws {
        let series = TimeSeries(changes: [
            StateChange(state: "unavailable", date: start),
            StateChange(state: "21", date: at(12)),
        ])
        let score = try #require(ComfortScore.compute(rooms: [("r", "Bureau", series)], range: 20...22, rangeOrigin: .entered, window: window))
        #expect(score.percent == 100)
    }

    @Test func noReadingMeansNoComfortScore() {
        let empty = TimeSeries(changes: [StateChange(state: "unavailable", date: start)])
        #expect(ComfortScore.compute(rooms: [("r", "Bureau", empty)], range: 20...22, rangeOrigin: .entered, window: window) == nil)
        #expect(ComfortScore.compute(rooms: [], range: 20...22, rangeOrigin: .entered, window: window) == nil)
    }

    // MARK: Energy

    @Test func energyComparesWithTheDayBeforeAtTheSameTime() throws {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: midnight))
        // 1 kWh an hour all day yesterday, 2 kWh an hour today until 10:00.
        let hourly = (0..<24).map { (start: yesterday.addingTimeInterval(Double($0) * 3600), value: 1.0) }
            + (0..<10).map { (start: midnight.addingTimeInterval(Double($0) * 3600), value: 2.0) }
        let now = midnight.addingTimeInterval(10 * 3600 + 600)
        let score = try #require(EnergyScore.compute(hourly: hourly, unit: "kWh", now: now))
        #expect(score.today == 20)
        #expect(score.dayBeforeAtThisTime == 10)

        let firstDay = try #require(EnergyScore.compute(hourly: Array(hourly.suffix(10)), unit: "kWh", now: now))
        #expect(firstDay.dayBeforeAtThisTime == nil)
    }

    @Test func energyScoresTheRatioToTheHabit() {
        #expect(EnergyScore.percent(ratio: 0.5) == 100)
        #expect(EnergyScore.percent(ratio: 0.7) == 100)
        #expect(EnergyScore.percent(ratio: 1) == 50)
        #expect(EnergyScore.percent(ratio: 1.25) == 25)
        #expect(EnergyScore.percent(ratio: 2) == 0)
    }

    @Test func energyComparesTodayWithTheSameHoursOfPreviousDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let midnight = calendar.startOfDay(for: start)
        let now = midnight.addingTimeInterval(10 * 3600)
        var hourly: [(start: Date, value: Double)] = []
        for day in 1...7 {
            for hour in 0..<24 {
                hourly.append((midnight.addingTimeInterval(Double(-day * 24 + hour) * 3600), 1))
            }
        }
        for hour in 0..<10 {
            hourly.append((midnight.addingTimeInterval(Double(hour) * 3600), 0.82))
        }

        let score = try #require(EnergyScore.compute(hourly: hourly, unit: "kWh", now: now, calendar: calendar))

        #expect(abs(score.today - 8.2) < 0.0001)
        #expect(score.usual == 10)
        #expect(abs((score.difference ?? 0) + 0.18) < 0.0001)
        #expect(score.percent == 80)
        #expect(score.lastDay.count == 24)
    }

    /// Readings that stop at midnight (a meter that reports the day after) score the day before, whole.
    @Test func readingsThatStopAtMidnightScoreYesterdayWhole() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let midnight = calendar.startOfDay(for: start)
        var hourly: [(start: Date, value: Double)] = []
        // Seven full days of 1 kWh an hour, then yesterday at 0.8: nothing for today yet.
        for day in 2...8 {
            for hour in 0..<24 { hourly.append((midnight.addingTimeInterval(Double(-day * 24 + hour) * 3600), 1)) }
        }
        for hour in 0..<24 { hourly.append((midnight.addingTimeInterval(Double(-24 + hour) * 3600), 0.8)) }

        let score = try #require(EnergyScore.compute(hourly: hourly, unit: "kWh", now: midnight.addingTimeInterval(9 * 3600), calendar: calendar))

        #expect(score.day == midnight.addingTimeInterval(-86_400))
        #expect(score.asOf == midnight)
        #expect(abs(score.today - 19.2) < 0.0001)
        #expect(score.usual == 24)
        #expect(score.percent == 83)
    }

    @Test func energyHasNoScoreBeforeThreeDaysOfHabit() throws {
        let midnight = Calendar.current.startOfDay(for: start)
        let hourly = (0..<30).map { (start: midnight.addingTimeInterval(Double($0 - 24) * 3600), value: 1.0) }
        let score = try #require(EnergyScore.compute(hourly: hourly, unit: "kWh", now: midnight.addingTimeInterval(6 * 3600)))
        #expect(score.usual == nil)
        #expect(score.percent == nil)
        #expect(EnergyScore.compute(hourly: [], unit: "kWh", now: start) == nil)
    }

    // MARK: Network

    @Test func networkFindsOutagesAndAvailability() throws {
        let connectivity = [
            StateChange(state: "on", date: start),
            StateChange(state: "off", date: at(3.2)),
            StateChange(state: "on", date: at(3.2).addingTimeInterval(240)),
            StateChange(state: "off", date: at(8)),
            StateChange(state: "on", date: at(8).addingTimeInterval(30)),
        ]
        let score = try #require(NetworkScore.compute(connectivity: connectivity, latency: nil, pastLatency: nil, window: window))

        #expect(score.outages == [DateInterval(start: at(3.2), duration: 240)])
        #expect(abs(score.availability - (86_400 - 270) / 86_400) < 0.000001)
        #expect(score.percent == 100)
    }

    @Test func slowAnswersOutsideTheHabitLowerTheNetworkScore() throws {
        let connectivity = [StateChange(state: "on", date: start)]
        var pastChanges: [StateChange] = []
        for index in 0..<48 {
            let date = start.addingTimeInterval(Double(-index - 1) * 3600)
            pastChanges.append(StateChange(state: String(10 + index % 10), date: date))
        }
        var todayChanges: [StateChange] = []
        for hour in 0..<10 {
            todayChanges.append(StateChange(state: hour < 5 ? "12" : "80", date: at(Double(hour))))
        }
        let past = TimeSeries(changes: pastChanges)
        let today = TimeSeries(changes: todayChanges)

        let score = try #require(NetworkScore.compute(connectivity: connectivity, latency: today, pastLatency: past, window: window))

        let usual = try #require(score.usualLatency)
        #expect(usual.lowerBound >= 10 && usual.upperBound < 20)
        #expect(score.latency.count == 10)
        #expect(score.percent == 80)
    }

    @Test func noConnectivityReadingMeansNoNetworkScore() {
        #expect(NetworkScore.compute(connectivity: [StateChange(state: "unavailable", date: start)], latency: nil, pastLatency: nil, window: window) == nil)
    }
}

struct ServerConfigTests {
    @Test func theServerSaysWhichTemperatureUnitItUses() throws {
        let fahrenheit = try JSONValue.object(["location_name": "Home", "unit_system": ["temperature": "°F", "length": "mi"]])
            .decode(ServerConfig.self)
        #expect(fahrenheit.usesFahrenheit)
        let celsius = try JSONValue.object(["location_name": "Maison", "unit_system": ["temperature": "°C"]]).decode(ServerConfig.self)
        #expect(!celsius.usesFahrenheit)
        #expect(try !JSONValue.object(["location_name": "Maison"]).decode(ServerConfig.self).usesFahrenheit)
    }
}
