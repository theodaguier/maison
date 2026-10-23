import Foundation
@testable import Maison
import Testing

struct RuleCatalogTests {
    @Test func readsAndWritesTheNewShapes() {
        let config: JSONValue = [
            "alias": "Tour de la maison",
            "triggers": [
                ["trigger": "time_pattern", "minutes": "/15"],
                ["trigger": "time_pattern", "hours": "/2", "minutes": 0],
                ["trigger": "calendar", "event": "start", "entity_id": "calendar.travail"],
            ],
            "conditions": [["condition": "numeric_state", "entity_id": "sensor.humidite_salle_de_bain", "above": 70]],
            "actions": [["action": "light.turn_off", "target": ["area_id": "bedroom"]]],
        ]
        let rule = AutomationRule(id: "tour", config: config)
        #expect(rule.triggers == [.interval(minutes: 15), .interval(minutes: 120), .calendar(entityID: "calendar.travail", atStart: true)])
        #expect(rule.conditions == [.threshold(entityID: "sensor.humidite_salle_de_bain", above: 70, below: nil)])
        #expect(rule.actions == [.roomLights(areaID: "bedroom", on: false)])
        #expect(AutomationRule(id: "tour", config: rule.config) == rule)
        #expect(rule.config["triggers"]?.arrayValue?[1] == ["trigger": "time_pattern", "hours": "/2", "minutes": 0])
    }

    @Test func keepsPatternsAndTargetsItCannotEdit() {
        let pattern: JSONValue = ["trigger": "time_pattern", "minutes": "5"]
        let offset: JSONValue = ["trigger": "calendar", "event": "start", "entity_id": "calendar.travail", "offset": "-0:15:0"]
        let areaAndDevice: JSONValue = ["action": "light.turn_on", "target": ["area_id": "bedroom", "device_id": "abc"]]
        let rule = AutomationRule(id: "x", config: ["alias": "X", "triggers": [pattern, offset], "actions": [areaAndDevice]])
        #expect(rule.triggers == [.other(pattern), .other(offset)])
        #expect(rule.actions == [.other(areaAndDevice)])
    }

    @MainActor
    @Test func offPeakStepsReadFromTheTariff() {
        let store = DemoHome.store()
        var rule = AutomationRule.new()
        rule.triggers = [.time(at: "22:00:00")]
        rule.actions = [.device(entityID: "switch.chauffe_eau", service: "switch.turn_on", data: [:]), .wait(minutes: 8 * 60)]

        #expect(store.catalogID(of: rule.triggers[0]) == "offPeak")
        #expect(store.describe(rule.triggers[0]).title == String(localized: "Off-peak hours start"))
        #expect(store.describe(rule.actions[1], in: rule).title == String(localized: "Wait for off-peak hours to end"))
        // The same wait without the off-peak trigger is just a wait.
        #expect(store.describe(rule.actions[1]).title == String(localized: "Wait \(480) min"))
        #expect(store.catalogID(of: .time(at: "19:00:00")) == "time")
        #expect(store.catalogID(of: .between(after: "22:00:00", before: "06:00:00")) == "offPeak")
        #expect(store.catalogID(of: .between(after: "23:00:00", before: "06:00:00")) == "time")
    }

    @MainActor
    @Test func theCatalogOnlyOffersWhatTheHomeCanDo() {
        let store = DemoHome.store()
        let triggers = store.triggerCatalog().flatMap(\.entries).map(\.id)
        #expect(triggers.contains("offPeak"))
        #expect(triggers.contains("internet"))
        // No calendar in the sample home.
        #expect(!triggers.contains("calendar"))

        let actions = store.actionCatalog(notifyServices: []).flatMap(\.entries).map(\.id)
        #expect(actions.contains("scene"))
        #expect(actions.contains("roomLights"))
        #expect(!actions.contains("notify"))
        #expect(!actions.contains("script"))
        #expect(store.actionCatalog(notifyServices: ["mobile_app_iphone"]).flatMap(\.entries).contains { $0.id == "notify" })

        let conditions = store.conditionCatalog().flatMap(\.entries).map(\.id)
        #expect(conditions.contains("person"))
        #expect(conditions.contains("threshold"))
    }

    @MainActor
    @Test func eachEntryMakesAStepThatComesBackToIt() {
        let store = DemoHome.store()
        for entry in store.triggerCatalog().flatMap(\.entries) {
            #expect(store.catalogID(of: entry.make()) == entry.id)
        }
        for entry in store.conditionCatalog().flatMap(\.entries) {
            #expect(store.catalogID(of: entry.make()) == entry.id)
        }
        for entry in store.actionCatalog(notifyServices: ["mobile_app_iphone"]).flatMap(\.entries) {
            #expect(store.catalogID(of: entry.make()) == entry.id)
        }
    }

    @Test func remembersRulesMaisonProposed() throws {
        let defaults = try #require(UserDefaults(suiteName: "RuleCatalogTests.\(UUID())"))
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ProposedRules.createdAt("r1", in: defaults) == nil)
        ProposedRules.add("r1", at: created, in: defaults)
        #expect(ProposedRules.createdAt("r1", in: defaults) == created)
        ProposedRules.remove("r1", in: defaults)
        #expect(ProposedRules.createdAt("r1", in: defaults) == nil)
    }
}
