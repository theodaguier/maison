import Foundation
import Testing
@testable import Maison

/// The model's reading of a request becomes a rule in Swift: these check that part, with the demo home.
@MainActor
struct RuleDraftTests {
    let devices = DemoHome.store().ruleDevices

    private func draft(
        when: String = "",
        _ trigger: RuleDraft.Trigger,
        night: Bool = false, sunset: Bool = false, someone: Bool = false, weekdays: Bool = false,
        _ actions: [RuleDraft.Action],
        unsupported: [String] = []
    ) -> RuleDraft {
        RuleDraft(whenWords: when, trigger: trigger, onlyAtNight: night, onlyAfterSunset: sunset,
                  onlyIfSomeoneIsHome: someone, onlyIfNobodyIsHome: false, onlyOnWeekdays: weekdays, onlyOnWeekend: false,
                  actions: actions, unsupported: unsupported, name: "règle test")
    }

    private func trigger(_ kind: RuleDraft.TriggerKind, place: String? = nil, time: String? = nil, value: Double? = nil) -> RuleDraft.Trigger {
        RuleDraft.Trigger(kind: kind, place: place, time: time, value: value)
    }

    private func action(_ kind: RuleDraft.ActionKind, _ target: String?, percent: Int? = nil) -> RuleDraft.Action {
        RuleDraft.Action(kind: kind, target: target, percent: percent, temperature: nil, minutes: nil, message: nil)
    }

    @Test func roomMeansItsLightsAndATimeWithTheSunIsAFixedTime() {
        let request = "Le soir à 19 h, si le soleil est couché et qu’on est là, allume le salon en lumière chaude et ferme les volets"
        let proposal = draft(when: "le soir à 19 h", trigger(.sunset), sunset: true, someone: true,
                             [action(.turnOn, "le salon", percent: 75), action(.closeBlinds, "les volets")])
            .proposal(for: request, devices: devices, notifyService: nil)

        #expect(proposal.rule.triggers == [.time(at: "19:00:00")])
        #expect(proposal.rule.conditions == [.afterSunset, .someoneHome])
        let lights = proposal.rule.actions.compactMap { action -> String? in
            if case .device(let id, "light.turn_on", let data) = action {
                // 75 % isn't in the request: the model made it up, so it's dropped. "Chaude" is warm white.
                #expect(data["brightness_pct"] == nil)
                #expect(data["color_temp_kelvin"] == .number(2700))
                return id
            }
            return nil
        }
        #expect(Set(lights) == Set(devices.filter { $0.kind == .light && $0.area == "Salon" }.map(\.id)))
        #expect(proposal.rule.actions.contains(.device(entityID: "cover.volets_salon", service: "cover.close_cover", data: [:])))
        #expect(!proposal.needsHelp)
        #expect(proposal.notes.count == 1)
        #expect(proposal.rule.name == "Règle test")
    }

    @Test func motionSensorIsFoundInTheRoomTheRuleActsOn() {
        let proposal = draft(trigger(.motionDetected), night: true, [action(.setBrightness, "le couloir", percent: 20)])
            .proposal(for: "La nuit, allume le couloir à 20 % s’il y a du mouvement", devices: devices, notifyService: nil)

        #expect(proposal.rule.triggers == [.state(entityID: "binary_sensor.couloir_motion", to: "on", forMinutes: nil)])
        #expect(proposal.rule.conditions == [.between(after: "23:00:00", before: "06:00:00")])
        #expect(proposal.rule.actions == [.device(entityID: "light.couloir", service: "light.turn_on", data: ["brightness_pct": 20])])
    }

    @Test func kindWordFindsTheDeviceNamedLikeIt() {
        let found = RuleDevice.matching("la clim", for: .turnOff, in: devices)
        #expect(found.devices.map(\.id) == ["climate.climatiseur"])
    }

    @Test func everythingIsLightsPlugsFansAndSpeakers() {
        let found = RuleDevice.matching("tout", for: .turnOff, in: devices)
        #expect(!found.devices.isEmpty)
        #expect(found.devices.allSatisfy { [.light, .switch, .fan, .mediaPlayer].contains($0.kind) })
    }

    @Test func unknownDeviceAndTriggerNeedHelp() {
        let request = "Quand l’électricité passe en heures creuses, lance le lave-linge"
        let proposal = draft(when: "Quand l’électricité passe en heures creuses", trigger(.deviceTurnsOff),
                             [action(.turnOn, "le lave-linge")], unsupported: ["Ferme"])
            .proposal(for: request, devices: devices, notifyService: nil)

        #expect(!proposal.isComplete)
        #expect(proposal.unsupported == ["Quand l’électricité passe en heures creuses"])
        #expect(proposal.unmatched == ["le lave-linge"])
    }

    @Test func thresholdNeedsTheValueOfTheRequest() {
        let made = draft(trigger(.temperatureRisesAbove, value: 25), [action(.closeBlinds, "les volets du salon")])
        let kept = made.proposal(for: "Ferme les volets du salon quand il fait plus de 25°", devices: devices, notifyService: nil)
        #expect(kept.rule.triggers == [.threshold(entityID: "sensor.salon_temperature", above: 25, below: nil)])

        let invented = made.proposal(for: "Ferme les volets du salon quand il fait chaud", devices: devices, notifyService: nil)
        #expect(invented.rule.triggers.isEmpty)
    }

    @Test func readsTimes() {
        #expect(RuleDraft.clockTime("19:00") == "19:00:00")
        #expect(RuleDraft.clockTime("7h30") == "07:30:00")
        #expect(RuleDraft.clockTime("25:00") == nil)
        #expect(RuleDraft.timeInSentence("Le matin en semaine à 7 h") == "07:00:00")
        #expect(RuleDraft.timeInSentence("la nuit") == nil)
    }
}
