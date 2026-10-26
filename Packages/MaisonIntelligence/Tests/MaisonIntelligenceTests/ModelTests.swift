import Foundation
@testable import MaisonIntelligence
import Testing

struct EntityStateValuesTests {
    @Test func attributesAreReadWithoutWording() {
        let climate = EntityState(entityID: "climate.salon", state: "heat", attributes: [
            "temperature": 21, "current_temperature": 19.5, "hvac_action": "heating",
        ])
        #expect(climate.kind == .climate)
        #expect(climate.targetTemperature == 21)
        #expect(climate.currentTemperature == 19.5)
        #expect(climate.temperatureStep == 0.5)
        #expect(climate.hvacAction == "heating")
        #expect(climate.isActive)

        let sensor = EntityState(entityID: "sensor.salon", state: "21.4", attributes: ["device_class": "temperature", "unit_of_measurement": "°C"])
        #expect(sensor.numericState == 21.4)
        #expect(sensor.deviceClass == "temperature")
        #expect(sensor.unit == "°C")
    }

    @Test func aLightsLevelComesFromItsBrightness() {
        let dimmed = EntityState(entityID: "light.salon", state: "on", attributes: ["brightness": 51])
        #expect(dimmed.level == 0.2)
        #expect(dimmed.supportsLevel)
        #expect(EntityState(entityID: "light.salon", state: "off").level == 0)
        #expect(!EntityState(entityID: "light.salon", state: "on", attributes: ["supported_color_modes": ["onoff"]]).supportsLevel)
    }

    @Test func homeAssistantTimestampsKeepTheirMilliseconds() throws {
        let date = try #require(EntityState.parseDate("2026-10-20T08:12:03.123456+00:00"))
        let seconds = try #require(EntityState.parseDate("2026-10-20T08:12:03+00:00"))
        #expect(abs(date.timeIntervalSince(seconds) - 0.123) < 0.0001)
    }
}

struct WordMatchingTests {
    @Test func foldingIgnoresCaseAccentsAndCurlyApostrophes() {
        #expect(WordMatching.fold("Salle d’Eau ÉTÉ") == "salle d'eau ete")
    }

    @Test func onlyWholeWordsMatch() {
        #expect(WordMatching.wholeWordRange(of: "bain", in: "salle de bain") != nil)
        #expect(WordMatching.wholeWordRange(of: "bain", in: "bains") == nil)
        #expect(WordMatching.wholeWordRange(of: "", in: "bain") == nil)
    }
}

struct HomeLayoutCodingTests {
    /// The layout is kept on the iPhone between launches: its keys must not change when the type moves.
    @Test func aStoredLayoutStillDecodes() throws {
        let stored = Data(#"{"areas":[{"area_id":"salon","name":"Salon","icon":"mdi:sofa"}],"areaByEntity":{"light.a":"salon"},"deviceByEntity":{},"hiddenEntities":[],"platformByEntity":{},"translationKeyByEntity":{}}"#.utf8)
        let layout = try JSONDecoder().decode(HomeLayout.self, from: stored)
        #expect(layout.areas == [Area(id: "salon", name: "Salon", icon: "mdi:sofa")])
        #expect(layout.areaByEntity["light.a"] == "salon")
        #expect(try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }
}
