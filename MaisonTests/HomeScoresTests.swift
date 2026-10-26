import Foundation
@testable import Maison
import Testing

struct HomeScoresTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var window: DateInterval { DateInterval(start: start, duration: 86_400) }

    private func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    // MARK: Comfort

    @Test func anEnteredComfortRangeIsKeptOnTheIPhone() throws {
        let defaults = try #require(UserDefaults(suiteName: "ComfortRange-\(UUID().uuidString)"))
        #expect(ComfortRangeSetting.range(in: defaults) == nil)
        ComfortRangeSetting.set(19.5...22, in: defaults)
        #expect(ComfortRangeSetting.range(in: defaults) == 19.5...22)
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

    // MARK: Summary

    @Test func theAirConditioningRunningWithNobodyHomeCanBeTurnedOff() {
        let inputs = HighlightInputs(cooling: ["climate.chambre"], someoneHome: false, openWindows: ["Fenêtre de la chambre"],
                                     hasThermometer: true, meterProposalSeen: true)
        let highlights = Highlights.compute(scores: HomeScores(computedAt: start), inputs: inputs, now: start)
        #expect(highlights.map(\.id) == ["cooling-away", "window-cooling"])
        #expect(highlights.allSatisfy { $0.climatesToTurnOff == ["climate.chambre"] && $0.hasOwnAction })
    }

    @Test func aHighlightShowsItsOriginUnlessItIsAMissingSource() {
        let measured = Highlight(id: "h", score: .network, fact: .connectedDevices(count: 2), origin: .measured, rank: .context)
        let missing = Highlight(id: "m", score: .energy, fact: .missingTariff, origin: .entered, rank: .missing)
        #expect(measured.showsOrigin)
        #expect(!missing.showsOrigin)
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

struct ScoresWithoutDeadEndTests {
    @Test func confirmingAMeterAddsItToTheGridAndKeepsTheRest() {
        let solar: JSONValue = ["type": "solar", "stat_energy_from": "sensor.solar"]
        // No grid yet: one is made for the meter.
        let made = EnergyPrefs.settingGridMeter("sensor.compteur", in: [solar])
        #expect(made.count == 2)
        #expect(made[0] == solar)
        #expect(made[1]["type"]?.stringValue == "grid")
        #expect(made[1]["flow_from"]?.arrayValue?.compactMap { $0["stat_energy_from"]?.stringValue } == ["sensor.compteur"])
        // A grid with a price already: the meter joins it, the price stays.
        let priced: JSONValue = ["type": "grid", "flow_from": [["stat_energy_from": "sensor.hc", "number_energy_price": 0.2]], "flow_to": []]
        let joined = EnergyPrefs.settingGridMeter("sensor.compteur", in: [priced])
        let flows = joined[0]["flow_from"]?.arrayValue ?? []
        #expect(flows.compactMap { $0["stat_energy_from"]?.stringValue } == ["sensor.hc", "sensor.compteur"])
        #expect(flows[0]["number_energy_price"]?.doubleValue == 0.2)
        // Already there: nothing changes.
        #expect(EnergyPrefs.settingGridMeter("sensor.hc", in: [priced]) == [priced])
    }

    @MainActor
    @Test func withoutPingTheBoxSaysWhetherTheInternetIsUp() {
        var layout = DemoHome.layout
        layout.platformByEntity["binary_sensor.box_wan"] = "fritz"
        layout.platformByEntity["sensor.box_download"] = "fritz"
        layout.platformByEntity["binary_sensor.vpn_laptop"] = "tailscale"
        let states = DemoHome.states.filter { layout.platformByEntity[$0.entityID] != "ping" } + [
            EntityState(entityID: "binary_sensor.vpn_laptop", state: "on", attributes: ["device_class": "connectivity"]),
            EntityState(entityID: "binary_sensor.box_wan", state: "on", attributes: ["device_class": "connectivity"]),
            EntityState(entityID: "sensor.box_download", state: "12", attributes: ["device_class": "data_rate", "unit_of_measurement": "MB/s"]),
        ]
        let store = HomeStore(
            demo: states,
            layout: layout,
            household: HouseholdStore(demo: DemoHome.household, members: DemoHome.members, plan: DemoHome.plan)
        )
        #expect(store.routerInternet?.entityID == "binary_sensor.box_wan")
    }
}
