import Foundation
@testable import MaisonIntelligence
import Testing

struct HighlightsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var window: DateInterval { DateInterval(start: start, duration: 86_400) }

    private func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    // MARK: Comfort range

    @Test func theRangeIsLearnedFromThreeDaysOfReadings() {
        #expect(ComfortRangeSetting.learned(from: Array(repeating: 21, count: 71)) == nil)
        let week = (0..<168).map { 20 + Double($0 % 21) / 10 }
        #expect(ComfortRangeSetting.learned(from: week) == 20.0...22.0)
    }

    @Test func aUsualRangeScoresFromTheFirstDayUntilOneIsLearned() {
        let first = ComfortRangeSetting.resolve(entered: nil, hourlyMeans: Array(repeating: 21, count: 10))
        #expect(first.range == 19...22)
        #expect(first.origin == .estimated)
        #expect(first.isStarting)

        let week = (0..<168).map { 20 + Double($0 % 21) / 10 }
        let learned = ComfortRangeSetting.resolve(entered: nil, hourlyMeans: week)
        #expect(learned.range == 20.0...22.0)
        #expect(!learned.isStarting)

        let entered = ComfortRangeSetting.resolve(entered: 18...21, hourlyMeans: [])
        #expect(entered.range == 18...21)
        #expect(entered.origin == .entered)
        #expect(!entered.isStarting)
    }

    @Test func aServerInFahrenheitStartsFromAFahrenheitRange() {
        let first = ComfortRangeSetting.resolve(entered: nil, hourlyMeans: [], fahrenheit: true)
        #expect(first.range == 66...72)
        #expect(first.isStarting)
        #expect(ComfortRangeSetting.editable(fahrenheit: true).bounds.contains(first.range.upperBound))
        #expect(ComfortRangeSetting.resolve(entered: nil, hourlyMeans: []).range == 19...22)
    }

    // MARK: Order

    @Test func anOutageComesBeforeARoomOutOfRange() throws {
        let comfort = try #require(ComfortScore.compute(
            rooms: [("bedroom", "Chambre", TimeSeries(changes: [StateChange(state: "25", date: start), StateChange(state: "21", date: at(2))]))],
            range: 20...22,
            rangeOrigin: .entered,
            window: window
        ))
        let network = try #require(NetworkScore.compute(
            connectivity: [StateChange(state: "on", date: start), StateChange(state: "off", date: at(3)), StateChange(state: "on", date: at(3.1))],
            latency: nil,
            pastLatency: nil,
            window: window
        ))
        let quiet = HighlightInputs(hasThermometer: true, meterProposalSeen: true)

        let both = Highlights.compute(scores: HomeScores(comfort: comfort, network: network, computedAt: start), inputs: quiet, now: start)
        #expect(both.map(\.score) == [.network, .comfort])
        #expect(both.first?.rank == .now)
        #expect(Highlights.compute(scores: HomeScores(comfort: comfort, computedAt: start), inputs: quiet, now: start).first?.score == .comfort)
        #expect(Highlights.compute(scores: HomeScores(computedAt: start), inputs: quiet, now: start).isEmpty)
    }

    @Test func aHomeWithoutMeterIsOfferedToReadItOnce() {
        let noMeter = HomeScores(computedAt: start)
        #expect(Highlights.compute(scores: noMeter, inputs: HighlightInputs(meterProposalSeen: false), now: start).map(\.fact) == [.missingMeter])
        #expect(Highlights.compute(scores: noMeter, inputs: HighlightInputs(meterProposalSeen: true), now: start).isEmpty)
        // With a meter, the next missing source is the tariff, then a thermometer.
        let metered = HomeScores(hasElectricityMeter: true, computedAt: start)
        #expect(Highlights.compute(scores: metered, inputs: HighlightInputs(), now: start).map(\.fact) == [.missingTariff])
        let price = EnergyPrice(perKilowattHour: 0.25, currency: "EUR", origin: .entered)
        #expect(Highlights.compute(scores: metered, inputs: HighlightInputs(price: price), now: start).map(\.fact) == [.missingThermometer])
        #expect(Highlights.compute(scores: metered, inputs: HighlightInputs(price: price, hasThermometer: true), now: start).isEmpty)
    }

    @Test func theHeatingRunningWithNobodyHomeComesFirst() {
        let inputs = HighlightInputs(heating: ["climate.salon"], someoneHome: false, openWindows: ["Fenêtre du salon"],
                                     hasThermometer: true, meterProposalSeen: true)
        let highlights = Highlights.compute(scores: HomeScores(computedAt: start), inputs: inputs, now: start)
        #expect(highlights.map(\.id) == ["heating-away", "window-heating"])
        #expect(highlights.allSatisfy { $0.rank == .now })
        // Someone home, windows shut: nothing to say about the heating.
        let home = HighlightInputs(heating: ["climate.salon"], someoneHome: true, hasThermometer: true, meterProposalSeen: true)
        #expect(Highlights.compute(scores: HomeScores(computedAt: start), inputs: home, now: start).isEmpty)
    }

    @Test func theAirConditioningRunningWithNobodyHomeIsCaughtToo() {
        let inputs = HighlightInputs(cooling: ["climate.chambre"], someoneHome: false, openWindows: ["Fenêtre de la chambre"],
                                     hasThermometer: true, meterProposalSeen: true)
        let highlights = Highlights.compute(scores: HomeScores(computedAt: start), inputs: inputs, now: start)
        #expect(highlights.map(\.id) == ["cooling-away", "window-cooling"])
        #expect(highlights.map(\.fact) == [
            .coolingWhileAway(entityIDs: ["climate.chambre"]),
            .windowOpenWhileCooling(window: "Fenêtre de la chambre", entityIDs: ["climate.chambre"]),
        ])
        // A window open with nothing heating or cooling isn't worth a word.
        let idle = HighlightInputs(openWindows: ["Fenêtre de la chambre"], hasThermometer: true, meterProposalSeen: true)
        #expect(Highlights.compute(scores: HomeScores(computedAt: start), inputs: idle, now: start).isEmpty)
    }

    // MARK: Energy

    @Test func aDeviceIsNamedOnlyWhenItUsesAFifthOfTheDay() {
        let energy = EnergyScore(today: 10, day: start, asOf: at(12), usual: nil, unit: "kWh", lastDay: [])
        let scores = HomeScores(energy: energy, hasElectricityMeter: true, computedAt: start)
        let price = EnergyPrice(perKilowattHour: 0.25, currency: "EUR", origin: .entered)
        func top(_ kWh: Double) -> [Highlight] {
            Highlights.compute(scores: scores, inputs: HighlightInputs(devices: [DeviceEnergy(id: "sensor.ce", name: "Chauffe-eau", kilowattHours: kWh)],
                                                                       price: price, hasThermometer: true), now: at(36))
                .filter { $0.id.hasPrefix("top-device") }
        }
        #expect(top(1.9).isEmpty)
        #expect(top(4).first?.fact == .topDevice(entityID: "sensor.ce", name: "Chauffe-eau", share: 0.4, kilowattHours: 4, isToday: false))
    }

    @Test func todayOrYesterdayIsToldFromNowNotTheClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let midnight = calendar.startOfDay(for: start)
        let energy = EnergyScore(today: 12, day: midnight, asOf: midnight.addingTimeInterval(12 * 3600), usual: 10, unit: "kWh", lastDay: [])
        let scores = HomeScores(energy: energy, hasElectricityMeter: true, computedAt: start)
        let inputs = HighlightInputs(price: EnergyPrice(perKilowattHour: 0.25, currency: "EUR", origin: .entered), hasThermometer: true)
        func habit(now: Date) -> Highlight.Fact? {
            Highlights.compute(scores: scores, inputs: inputs, now: now, calendar: calendar).first { $0.id == "energy-habit" }?.fact
        }
        let sameDay = try #require(habit(now: midnight.addingTimeInterval(13 * 3600)))
        let nextDay = try #require(habit(now: midnight.addingTimeInterval(30 * 3600)))
        guard case .energyAboveHabit(let difference, let isToday) = sameDay, case .energyAboveHabit(_, let isYesterday) = nextDay else {
            Issue.record("Both are the day above the habit")
            return
        }
        #expect(abs(difference - 0.2) < 0.0001)
        #expect(isToday)
        #expect(!isYesterday)
    }

    @Test func whatNeverSwitchesOffIsTheLowestHoursOfTheWeek() {
        let hours = (0..<100).map { (start: at(Double($0)), value: $0 % 10 == 0 ? 0.08 : 0.5) }
        #expect(Highlights.alwaysOnWatts(Array(hours.prefix(71))) == nil)
        #expect(Highlights.alwaysOnWatts(hours) == 80)
    }
}
