import Foundation
@testable import MaisonIntelligence
import Testing

struct DayFactsTests {
    /// A midnight away from daylight saving changes, so yesterday is 24 hours earlier.
    private let day = DateInterval(
        start: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)),
        duration: 86_400
    )

    private func at(_ hours: Double) -> Date { day.start.addingTimeInterval(hours * 3600) }

    private func point(_ hours: Double, max: Double) -> StatisticPoint {
        StatisticPoint(start: at(hours), mean: nil, min: nil, max: max)
    }

    // MARK: Temperature

    @Test func temperaturePeakIsTheWarmestHourAcrossThermometers() {
        let inputs = DayInputs(thermometers: [
            .init(entityID: "sensor.salon", room: "Salon", points: [point(-10, max: 21), point(14, max: 23.4)]),
            .init(entityID: "sensor.chambre", room: nil, points: [point(-9, max: 22), point(15, max: 22.5)]),
        ])
        guard case .temperaturePeak(let entityID, let room, let degrees, let hour, .more(let difference)?)? =
            DayFacts.compute(inputs, day: day, now: at(20)).first else {
            Issue.record("No warmer peak")
            return
        }
        #expect(entityID == "sensor.salon" && room == "Salon" && degrees == 23.4 && hour == at(14))
        #expect(abs(difference - 1.4) < 0.001)
    }

    @Test func temperatureWithinAThirdOfADegreeIsTheSame() {
        let inputs = DayInputs(thermometers: [.init(entityID: "sensor.salon", room: nil, points: [point(-10, max: 22), point(14, max: 22.2)])])
        let fact = DayFacts.temperaturePeak(inputs.thermometers, day: day)
        #expect(fact == .temperaturePeak(entityID: "sensor.salon", room: nil, degrees: 22.2, hour: at(14), versusYesterday: .same))
    }

    @Test func temperatureWithoutYesterdayHasNoComparison() {
        let fact = DayFacts.temperaturePeak([.init(entityID: "sensor.salon", room: nil, points: [point(14, max: 20)])], day: day)
        #expect(fact == .temperaturePeak(entityID: "sensor.salon", room: nil, degrees: 20, hour: at(14), versusYesterday: nil))
        #expect(DayFacts.temperaturePeak([.init(entityID: "sensor.salon", room: nil, points: [point(-3, max: 20)])], day: day) == nil)
    }

    // MARK: Climate

    @Test func climateRunsOnlyWhenOnFiveMinutesOrMore() {
        let long = DayInputs.Climate(entityID: "climate.chambre", name: "Climatiseur", room: "Chambre", target: 21, changes: [
            StateChange(state: "off", date: day.start), StateChange(state: "cool", date: at(13)), StateChange(state: "off", date: at(15.5)),
        ])
        let short = DayInputs.Climate(entityID: "climate.salon", name: "Radiateur", room: nil, target: nil, changes: [
            StateChange(state: "heat", date: at(10)), StateChange(state: "off", date: at(10.05)),
        ])
        let facts = DayFacts.climateRuns([long, short], day: day, now: at(20))
        #expect(facts == [.climateRun(entityID: "climate.chambre", name: "Climatiseur", room: "Chambre", duration: 2.5 * 3600, target: 21, heating: false)])
    }

    @Test func climateThatHeatedIsHeating() {
        let climate = DayInputs.Climate(entityID: "climate.salon", name: "Radiateur", room: nil, target: nil, changes: [
            StateChange(state: "heat", date: at(6)), StateChange(state: "off", date: at(8)),
        ])
        guard case .climateRun(_, _, _, _, _, let heating)? = DayFacts.climateRuns([climate], day: day, now: at(20)).first else {
            Issue.record("No run")
            return
        }
        #expect(heating)
    }

    // MARK: Locks

    @Test func lockKeepsTheLastChangeAndWhoMadeIt() {
        let lock = DayInputs.Lock(entityID: "lock.porte", name: "Porte", entries: [
            LogbookEntry(date: at(-1), state: "locked", userID: "theo", automationName: nil),
            LogbookEntry(date: at(7.9), state: "unlocked", userID: "theo", automationName: nil),
            LogbookEntry(date: at(8.2), state: "locked", userID: nil, automationName: "Dernier départ"),
        ])
        #expect(DayFacts.lockEvents([lock], day: day, people: [:])
            == [.lock(entityID: "lock.porte", name: "Porte", locked: true, at: at(8.2), by: .automation("Dernier départ"))])

        let byPerson = DayInputs.Lock(entityID: "lock.porte", name: "Porte", entries: [
            LogbookEntry(date: at(7.9), state: "unlocked", userID: "theo", automationName: nil),
        ])
        #expect(DayFacts.lockEvents([byPerson], day: day, people: ["theo": "Théo"])
            == [.lock(entityID: "lock.porte", name: "Porte", locked: false, at: at(7.9), by: .person("Théo"))])
        #expect(DayFacts.lockEvents([byPerson], day: day, people: [:])
            == [.lock(entityID: "lock.porte", name: "Porte", locked: false, at: at(7.9), by: nil)])
    }

    @Test func lockUntouchedTodayHasNoFact() {
        let lock = DayInputs.Lock(entityID: "lock.porte", name: "Porte", entries: [
            LogbookEntry(date: at(-5), state: "locked", userID: nil, automationName: nil),
        ])
        #expect(DayFacts.lockEvents([lock], day: day, people: [:]).isEmpty)
    }

    // MARK: Energy

    private func energy(today: Double, yesterdayAtThisTime: Double?, day scored: Date) -> EnergyScore {
        var history: [(start: Date, value: Double)] = [(at(9), today)]
        if let yesterdayAtThisTime { history.insert((at(9 - 24), yesterdayAtThisTime), at: 0) }
        return EnergyScore(today: today, day: scored, asOf: at(10), usual: nil, unit: "kWh", lastDay: history, history: history)
    }

    @Test func energyComparesWithYesterdayInPercent() {
        #expect(DayFacts.energyUse(energy(today: 4.2, yesterdayAtThisTime: 5, day: day.start), day: day)
            == .energyUse(amount: 4.2, unit: "kWh", versusYesterday: .less(16)))
        #expect(DayFacts.energyUse(energy(today: 5, yesterdayAtThisTime: 4, day: day.start), day: day)
            == .energyUse(amount: 5, unit: "kWh", versusYesterday: .more(25)))
        #expect(DayFacts.energyUse(energy(today: 4.001, yesterdayAtThisTime: 4, day: day.start), day: day)
            == .energyUse(amount: 4.001, unit: "kWh", versusYesterday: .same))
        #expect(DayFacts.energyUse(energy(today: 4, yesterdayAtThisTime: nil, day: day.start), day: day)
            == .energyUse(amount: 4, unit: "kWh", versusYesterday: nil))
    }

    @Test func energyAboutAnotherDayIsLeftOut() {
        let score = energy(today: 4.2, yesterdayAtThisTime: nil, day: day.start.addingTimeInterval(-86_400))
        #expect(DayFacts.energyUse(score, day: day) == nil)
        #expect(DayFacts.energyUse(nil, day: day) == nil)
    }

    // MARK: Automations

    @Test func automationsBusiestFirstAtMostThree() {
        let runs = [
            AutomationRun(automationID: "soir", start: at(-5), execution: "finished"),
            AutomationRun(automationID: "depart", start: at(8.2), execution: "finished"),
            AutomationRun(automationID: "couloir", start: at(1.2), execution: "finished"),
            AutomationRun(automationID: "couloir", start: at(2.5), execution: "finished"),
            AutomationRun(automationID: "couloir", start: at(4.5), execution: "failed_conditions"),
            AutomationRun(automationID: "a", start: at(9), execution: "finished"),
            AutomationRun(automationID: "b", start: at(10), execution: "finished"),
        ]
        let facts = DayFacts.automationRuns(runs, names: ["couloir": "Couloir la nuit", "depart": "Dernier départ"], day: day)
        #expect(facts == [
            .automationRuns(name: "Couloir la nuit", count: 2),
            .automationRuns(name: "Dernier départ", count: 1),
            .automationRuns(name: "a", count: 1),
        ])
    }

    // MARK: Order

    @Test func factsComeInTheSheetsOrder() {
        let inputs = DayInputs(
            thermometers: [.init(entityID: "sensor.salon", room: nil, points: [point(14, max: 20)])],
            locks: [.init(entityID: "lock.porte", name: "Porte", entries: [LogbookEntry(date: at(8), state: "locked", userID: nil, automationName: nil)])],
            automationRuns: [AutomationRun(automationID: "x", start: at(9), execution: "finished")]
        )
        #expect(DayFacts.compute(inputs, day: day, now: at(20)).map(\.id) == ["temperature", "lock.lock.porte", "automation.x"])
    }
}
