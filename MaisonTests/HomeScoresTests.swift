import Foundation
@testable import Maison
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

    @Test func theRangeIsLearnedFromThreeDaysOfReadings() {
        #expect(ComfortRangeSetting.learned(from: Array(repeating: 21, count: 71)) == nil)
        let week = (0..<168).map { 20 + Double($0 % 21) / 10 }
        #expect(ComfortRangeSetting.learned(from: week) == 20.0...22.0)
    }

    @Test func aUsualRangeScoresFromTheFirstDayUntilOneIsLearned() {
        let first = ComfortRangeSetting.resolve(entered: nil, hourlyMeans: Array(repeating: 21, count: 10))
        #expect(first.range == ComfortRangeSetting.starting)
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

    @MainActor
    @Test func aThermometerNotInARoomYetStillCounts() {
        let added = EntityState(entityID: "sensor.thermometre_neuf", state: "20.5", attributes: [
            "friendly_name": "Thermomètre", "device_class": "temperature", "unit_of_measurement": "°C",
        ])
        let store = HomeStore(
            demo: DemoHome.states + [added],
            layout: DemoHome.layout,
            household: HouseholdStore(demo: DemoHome.household, members: DemoHome.members, plan: DemoHome.plan)
        )
        let sensors = store.comfortSensors
        // Rooms first, then the one not in a room, under its own name.
        #expect(sensors.count == store.roomTemperatureSensors.count + 1)
        #expect(sensors.last?.id == "sensor.thermometre_neuf")
        #expect(sensors.last?.name == "Thermomètre")
        #expect(sensors.dropLast().map(\.id) == store.roomTemperatureSensors.map(\.area.id))
    }

    @MainActor
    @Test func outdoorThermometersAreToldByTheirRoomAndIntegrationNotTheirName() {
        func thermometer(_ id: String, _ name: String) -> EntityState {
            EntityState(entityID: id, state: "12", attributes: [
                "friendly_name": .string(name), "device_class": "temperature", "unit_of_measurement": "°C",
            ])
        }
        var layout = DemoHome.layout
        layout.areas.append(Area(id: "jardin", name: "Jardin", icon: "mdi:tree"))
        layout.areaByEntity["sensor.jardin"] = "jardin"
        layout.areaByEntity["sensor.sonde_salon"] = "living_room"
        layout.platformByEntity["sensor.prevision"] = "met"
        let store = HomeStore(
            demo: DemoHome.states + [
                thermometer("sensor.jardin", "Sonde"),
                thermometer("sensor.prevision", "Temperatur"),
                thermometer("sensor.sonde_salon", "Outdoor probe"),
                thermometer("sensor.sonde_libre", "Außentemperatur"),
            ],
            layout: layout,
            household: HouseholdStore(demo: DemoHome.household, members: DemoHome.members, plan: DemoHome.plan)
        )
        let indoor = Set(store.indoorTemperatureSensors.map(\.entityID))
        // In a garden, or from a forecast service: outside, whatever the name.
        #expect(!indoor.contains("sensor.jardin"))
        #expect(!indoor.contains("sensor.prevision"))
        // In the living room: inside, even named "outdoor".
        #expect(indoor.contains("sensor.sonde_salon"))
        // In no room: it counts until it is placed outdoors, in any language.
        #expect(indoor.contains("sensor.sonde_libre"))
        #expect(indoor.contains("sensor.salon_temperature"))
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

    @Test func theEnergyRingShowsTodaysUseUntilThereIsAHabit() {
        let learning = EnergyScore(today: 3.25, usual: nil, unit: "kWh", lastDay: [])
        let scores = HomeScores(energy: learning, computedAt: start)
        #expect(ScoreKind.energy.percent(in: scores) == nil)
        #expect(ScoreKind.energy.reading(in: scores)?.unit == "kWh")
        #expect(ScoreKind.energy.reading(in: scores)?.value == 3.25.formatted(.number.precision(.fractionLength(0...1))))

        let habit = EnergyScore(today: 2, usual: 2, unit: "kWh", lastDay: [])
        #expect(ScoreKind.energy.reading(in: HomeScores(energy: habit, computedAt: start)) == nil)
        #expect(ScoreKind.comfort.reading(in: scores) == nil)
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

    // MARK: Summary

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

        let both = Highlights.compute(scores: HomeScores(comfort: comfort, network: network, computedAt: start), inputs: quiet)
        #expect(both.map(\.score) == [.network, .comfort])
        #expect(both.first?.rank == .now)
        #expect(Highlights.compute(scores: HomeScores(comfort: comfort, computedAt: start), inputs: quiet).first?.score == .comfort)
        #expect(Highlights.compute(scores: HomeScores(computedAt: start), inputs: quiet).isEmpty)
    }

    @Test func aHomeWithoutMeterIsOfferedToReadItOnce() {
        let noMeter = HomeScores(computedAt: start)
        #expect(Highlights.compute(scores: noMeter, inputs: HighlightInputs(meterProposalSeen: false)).map(\.fact) == [.missingMeter])
        #expect(Highlights.compute(scores: noMeter, inputs: HighlightInputs(meterProposalSeen: true)).isEmpty)
        // With a meter, the next missing source is the tariff, then a thermometer.
        let metered = HomeScores(hasElectricityMeter: true, computedAt: start)
        #expect(Highlights.compute(scores: metered, inputs: HighlightInputs()).map(\.fact) == [.missingTariff])
        let price = EnergyPrice(perKilowattHour: 0.25, currency: "EUR", origin: .entered)
        #expect(Highlights.compute(scores: metered, inputs: HighlightInputs(price: price)).map(\.fact) == [.missingThermometer])
        #expect(Highlights.compute(scores: metered, inputs: HighlightInputs(price: price, hasThermometer: true)).isEmpty)
    }

    @Test func theHeatingRunningWithNobodyHomeComesFirst() {
        let inputs = HighlightInputs(heating: ["climate.salon"], someoneHome: false, openWindows: ["Fenêtre du salon"],
                                     hasThermometer: true, meterProposalSeen: true)
        let highlights = Highlights.compute(scores: HomeScores(computedAt: start), inputs: inputs)
        #expect(highlights.map(\.id) == ["heating-away", "window-heating"])
        #expect(highlights.allSatisfy { $0.rank == .now })
        // Someone home, windows shut: nothing to say about the heating.
        let home = HighlightInputs(heating: ["climate.salon"], someoneHome: true, hasThermometer: true, meterProposalSeen: true)
        #expect(Highlights.compute(scores: HomeScores(computedAt: start), inputs: home).isEmpty)
    }

    @Test func aDeviceIsNamedOnlyWhenItUsesAFifthOfTheDay() {
        let energy = EnergyScore(today: 10, day: start, asOf: at(12), usual: nil, unit: "kWh", lastDay: [])
        let scores = HomeScores(energy: energy, hasElectricityMeter: true, computedAt: start)
        let price = EnergyPrice(perKilowattHour: 0.25, currency: "EUR", origin: .entered)
        func top(_ kWh: Double) -> [Highlight] {
            Highlights.compute(scores: scores, inputs: HighlightInputs(devices: [DeviceEnergy(id: "sensor.ce", name: "Chauffe-eau", kilowattHours: kWh)],
                                                                       price: price, hasThermometer: true))
                .filter { $0.id.hasPrefix("top-device") }
        }
        #expect(top(1.9).isEmpty)
        #expect(top(4).first?.fact == .topDevice(entityID: "sensor.ce", name: "Chauffe-eau", share: 0.4, kilowattHours: 4, isToday: false))
    }

    @Test func whatNeverSwitchesOffIsTheLowestHoursOfTheWeek() {
        let hours = (0..<100).map { (start: at(Double($0)), value: $0 % 10 == 0 ? 0.08 : 0.5) }
        #expect(Highlights.alwaysOnWatts(Array(hours.prefix(71))) == nil)
        let watts = try? #require(Highlights.alwaysOnWatts(hours))
        #expect(watts == 80)
    }

    @Test func aSectionButtonOnlyShowsWhenItDoesMoreThanOpenTheFiche() {
        func highlight(_ fact: Highlight.Fact) -> Highlight { Highlight(id: "h", score: .network, fact: fact, origin: .measured, rank: .context) }
        #expect(!highlight(.connectedDevices(count: 2)).hasOwnAction)
        #expect(!highlight(.outage(start: start, duration: 120)).hasOwnAction)
        #expect(highlight(.heatingWhileAway(entityIDs: ["climate.salon"])).hasOwnAction)
        #expect(highlight(.missingThermometer).hasOwnAction)
        #expect(highlight(.missingTariff).hasOwnAction)
        #expect(highlight(.topDevice(entityID: "sensor.ce", name: "Chauffe-eau", share: 0.4, kilowattHours: 4, isToday: true)).hasOwnAction)
    }

    @Test func theNetworkSectionSaysWhatTheScoreIsMadeOf() throws {
        let network = try #require(NetworkScore.compute(
            connectivity: [StateChange(state: "on", date: start)],
            latency: TimeSeries(changes: [StateChange(state: "4", date: at(1))]),
            pastLatency: nil,
            window: window
        ))
        let stats = NetworkSection.stats(network, router: (download: nil, devices: 2))
        #expect(stats.map(\.value) == ["100 %", "0", "4 ms", "2"])
        #expect(NetworkSection.stats(network, router: (download: "512 Mbit/s", devices: 2)).last?.value == "512 Mbit/s")
    }

    @Test func theFingerPicksTheClosestReading() {
        let points = [(date: at(1), value: 10.0), (date: at(2), value: 20.0), (date: at(4), value: 40.0)]
        #expect(nearest(points, to: at(2.4), at: \.date)?.value == 20)
        #expect(nearest(points, to: at(3.6), at: \.date)?.value == 40)
        #expect(nearest([(date: Date, value: Double)](), to: at(1), at: \.date) == nil)
    }

    // MARK: Home layout

    @Test func aSectionWithSomethingToFixMovesAheadOfTheOtherScores() {
        let layout = HomeLayoutSetting(shown: [.summary, .shortcuts, .comfort, .energy, .network])
        #expect(layout.arranged(withFindings: []) == layout.shown)
        #expect(layout.arranged(withFindings: [.network]) == [.summary, .shortcuts, .network, .comfort, .energy])
        #expect(layout.arranged(withFindings: [.energy, .network]) == [.summary, .shortcuts, .energy, .network, .comfort])
        // The person's own order holds: shortcuts placed between scores stay where they are.
        let mixed = HomeLayoutSetting(shown: [.comfort, .shortcuts, .network])
        #expect(mixed.arranged(withFindings: [.network]) == [.network, .shortcuts, .comfort])
        #expect(HomeLayoutSetting.standard.hidden == [.weather, .monthCost])
    }

    @Test func theHomeLayoutIsKeptOnTheIPhone() throws {
        let defaults = try #require(UserDefaults(suiteName: "HomeLayout-\(UUID().uuidString)"))
        #expect(HomeLayoutSetting.load(from: defaults) == .standard)
        HomeLayoutSetting(shown: [.energy, .weather, .energy]).save(to: defaults)
        #expect(HomeLayoutSetting.load(from: defaults).shown == [.energy, .weather])
    }

    @Test func theRibbonMarksTheHalfHoursWithAnOutage() {
        let day = DateInterval(start: start, duration: 86_400)
        let slices = HomeVisuals.availability(outages: [DateInterval(start: at(14), duration: 120)], known: DateInterval(start: at(6), end: day.end), window: day)
        #expect(slices.count == 48)
        #expect(slices[28] == .down)
        #expect(slices[27] == .up && slices[29] == .up)
        #expect(slices[0] == .unknown && slices[11] == .unknown && slices[12] == .up)
    }

    @Test func aRoomSitsOnAScaleThatHoldsTheRange() {
        let scale = HomeVisuals.scale(range: 20...22, values: [21, 24])
        #expect(scale == 18...26)
        #expect(HomeVisuals.position(of: 22, on: scale) == 0.5)
        #expect(HomeVisuals.position(of: 30, on: scale) == 1)
    }

    // MARK: Meter reading

    @Test func theWayToReadTheMeterFollowsTheCountry() {
        #expect(MeterReading.forCountry("FR") == .port(.tic))
        #expect(MeterReading.forCountry("nl") == .port(.p1))
        #expect(MeterReading.forCountry("BE") == .port(.p1))
        #expect(MeterReading.forCountry("SE") == .port(.han))
        // Anywhere else, a clamp in the electrical panel works with any meter.
        #expect(MeterReading.forCountry("US") == .clamp)
        #expect(MeterReading.forCountry("JP") == .clamp)
    }

    @Test func withoutACountryOnTheServerTheIPhoneRegionDecides() {
        #expect(MeterReading.forCountry(nil, region: "NO") == .port(.han))
        #expect(MeterReading.forCountry(nil, region: nil) == .clamp)
        #expect(MeterReading.forCountry("DE", region: "FR") == .clamp)
    }
}
