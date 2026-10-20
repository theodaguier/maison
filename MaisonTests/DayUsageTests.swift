import Foundation
import Testing
@testable import Maison

struct DayUsageTests {
    let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400)

    private func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: hours * 3600) }

    @Test func addsUpOnPeriods() {
        let usage = DayUsage(changes: [
            StateChange(state: "off", date: at(0)),
            StateChange(state: "on", date: at(7)),
            StateChange(state: "off", date: at(8)),
            StateChange(state: "on", date: at(19)),
            StateChange(state: "off", date: at(20.5)),
        ], day: day, now: at(23))

        #expect(usage.periods.count == 2)
        #expect(usage.total == 2.5 * 3600)
    }

    @Test func stillOnRunsUntilNow() {
        let usage = DayUsage(changes: [StateChange(state: "on", date: at(18))], day: day, now: at(19))
        #expect(usage.total == 3600)
    }

    @Test func ignoresUnavailableAsOff() {
        let usage = DayUsage(changes: [
            StateChange(state: "on", date: at(1)),
            StateChange(state: "unavailable", date: at(2)),
        ], day: day, now: at(5))
        #expect(usage.total == 3600)
    }
}

struct DayUsageAfterTheDayTests {
    /// Yesterday's usage is built from a history that continues into today; it used to crash.
    @Test func ignoresChangesAfterTheDay() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let day = DateInterval(start: start, duration: 86_400)
        let usage = DayUsage(
            changes: [
                StateChange(state: "off", date: start),
                StateChange(state: "on", date: start.addingTimeInterval(90_000)),
                StateChange(state: "off", date: start.addingTimeInterval(95_000)),
            ],
            day: day,
            now: start.addingTimeInterval(100_000)
        )
        #expect(usage.periods.isEmpty)
    }
}
