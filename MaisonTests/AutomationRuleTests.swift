import Foundation
import Testing
@testable import Maison

struct AutomationRuleTests {
    @Test func readsTheCommonShapes() {
        let config: JSONValue = [
            "alias": "Lumières du soir",
            "trigger": [["platform": "time", "at": "19:00:00"]],
            "condition": [["condition": "sun", "after": "sunset"], ["condition": "numeric_state", "entity_id": "zone.home", "above": 0]],
            "action": [
                ["service": "light.turn_on", "target": ["entity_id": "light.lampadaire"], "data": ["brightness_pct": 60]],
                ["delay": "00:02:00"],
                ["action": "scene.turn_on", "target": ["entity_id": "scene.cinema"]],
            ],
            "mode": "restart",
        ]
        let rule = AutomationRule(id: "soir", config: config)
        #expect(rule.name == "Lumières du soir")
        #expect(rule.triggers == [.time(at: "19:00:00")])
        #expect(rule.conditions == [.afterSunset, .someoneHome])
        #expect(rule.actions == [
            .device(entityID: "light.lampadaire", service: "light.turn_on", data: ["brightness_pct": 60]),
            .wait(minutes: 2),
            .scene(entityID: "scene.cinema"),
        ])
        #expect(rule.extra["mode"] == "restart")
    }

    @Test func keepsWhatItDoesNotUnderstand() {
        let template: JSONValue = ["trigger": "template", "value_template": "{{ true }}"]
        let choose: JSONValue = ["choose": [["conditions": [], "sequence": []]]]
        let rule = AutomationRule(id: "x", config: ["alias": "X", "triggers": [template], "actions": [choose]])
        #expect(rule.triggers == [.other(template)])
        #expect(rule.actions == [.other(choose)])
        #expect(rule.config["triggers"] == [template])
        #expect(rule.config["actions"] == [choose])
    }

    @Test func roundTripsThroughItsConfig() {
        var rule = AutomationRule.new()
        rule.name = "Dernier départ"
        rule.triggers = [.everyoneLeaves, .sun(.sunset, offset: -30), .state(entityID: "binary_sensor.porte", to: "on", forMinutes: 10)]
        rule.conditions = [.between(after: "23:00:00", before: "06:00:00"), .weekdays(["sat", "sun"])]
        rule.actions = [.device(entityID: "lock.porte", service: "lock.lock", data: [:]), .notify(service: "mobile_app_iphone", message: "Fermé")]
        let reread = AutomationRule(id: rule.id, config: rule.config)
        #expect(reread == rule)
    }

    @Test func readsSunOffsets() {
        let rule = AutomationRule(id: "s", config: ["triggers": [["trigger": "sun", "event": "sunrise", "offset": "-01:15:00"]]])
        #expect(rule.triggers == [.sun(.sunrise, offset: -75)])
    }

    @Test func roundTripsTheAddedSteps() {
        var rule = AutomationRule.new()
        rule.name = "Catalogue"
        rule.triggers = [.every(minutes: 15), .every(minutes: 120), .calendar(entityID: "calendar.travail", start: true, offset: -15),
                         .person(entityID: "person.theo", arrives: true), .tag(id: "entree"), .serverStarts]
        rule.conditions = [.daytime, .nighttime, .person(entityID: "person.theo", isHome: false),
                           .threshold(entityID: "sensor.humidite", above: 70, below: nil)]
        rule.actions = [.lights(areaID: "chambre", on: false), .lights(areaID: nil, on: false), .script(entityID: "script.arrosage"),
                        .rule(entityID: "automation.volets", command: .turnOff)]
        let reread = AutomationRule(id: rule.id, config: rule.config)
        #expect(reread == rule)
    }

    @Test func readsTheAddedShapesFromHomeAssistant() {
        let config: JSONValue = [
            "triggers": [
                ["trigger": "time_pattern", "minutes": "/30"],
                ["trigger": "time_pattern", "hours": "/2"],
                ["trigger": "homeassistant", "event": "shutdown"],
            ],
            "conditions": [["condition": "state", "entity_id": "person.theo", "state": "home"]],
            "actions": [["action": "light.turn_off", "target": ["entity_id": "all"]], ["action": "automation.trigger", "target": ["entity_id": "automation.x"]]],
        ]
        let rule = AutomationRule(id: "c", config: config)
        // Every minute of every other hour is not "every 2 hours": kept as written.
        #expect(rule.triggers.first == .every(minutes: 30))
        #expect(rule.triggers.dropFirst().allSatisfy { if case .other = $0 { true } else { false } })
        #expect(rule.conditions == [.person(entityID: "person.theo", isHome: true)])
        #expect(rule.actions == [.lights(areaID: nil, on: false), .rule(entityID: "automation.x", command: .trigger)])
    }
}
