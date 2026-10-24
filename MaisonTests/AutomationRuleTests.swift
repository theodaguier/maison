import Foundation
@testable import Maison
import Testing

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
}
