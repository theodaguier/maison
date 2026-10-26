import Foundation

// The one tap that fixes a finding: the rule Maison proposes, built from the finding's facts.

extension Finding {
    /// The rule the main button creates, new each time it is asked for; `nil` when nothing in the home
    /// can switch the device.
    var rule: AutomationRule? {
        switch kind {
        case .peakHours:
            guard let switchEntityID, let offPeak else { return nil }
            var proposal = AutomationRule.new()
            proposal.name = String(localized: "\(deviceName) in off-peak hours")
            proposal.description = String(localized: "Created by Maison: runs only during the off-peak hours of your tariff.")
            proposal.triggers = [.time(at: String(format: "%02d:00:00", offPeak.startHour))]
            proposal.actions = [
                .device(entityID: switchEntityID, service: "switch.turn_on", data: [:]),
                .wait(minutes: offPeak.duration * 60),
                .device(entityID: switchEntityID, service: "switch.turn_off", data: [:]),
            ]
            return proposal
        }
    }
}
