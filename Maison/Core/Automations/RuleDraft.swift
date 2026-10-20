import Foundation
import FoundationModels

/// A rule as the on-device model fills it from a request: a closed set of the simple shapes the editor
/// understands. Swift checks every device and value before it becomes an `AutomationRule`.
@Generable
struct RuleDraft: Sendable {
    @Guide(description: "The request restated in plain English: when it starts, the conditions if any, then what to do.")
    var understanding: String

    @Guide(description: "A short name for the rule, two to four words, in the language of the request.")
    var name: String

    var trigger: Trigger

    @Guide(description: "Only the conditions the request states. Usually empty.")
    var conditions: [Condition]

    @Guide(description: "What the rule does, in order, one action per device.")
    var actions: [Action]

    @Guide(description: "Parts of the request left out of the rule because no kind expresses them, copied word for word from the request. Usually empty.")
    var unsupported: [String]

    @Generable
    enum TriggerKind: Sendable {
        case atTime, atSunset, atSunrise, whenEveryoneHasLeft, whenSomeoneArrivesHome, whenDeviceChanges, whenValueRisesAbove, whenValueFallsBelow
    }

    @Generable
    struct Trigger: Sendable {
        var kind: TriggerKind
        @Guide(description: "24-hour time such as 19:00, for atTime.")
        var time: String?
        @Guide(description: "Minutes after (positive) or before (negative) the sun event, for atSunset and atSunrise.")
        var offsetMinutes: Int?
        @Guide(description: "A device id from the list, for whenDeviceChanges, whenValueRisesAbove and whenValueFallsBelow.")
        var deviceID: String?
        @Guide(description: "The state the device changes to: on, off, open, closed, locked, unlocked or detected.")
        var toState: String?
        @Guide(description: "The threshold, for whenValueRisesAbove and whenValueFallsBelow.")
        var value: Double?
    }

    @Generable
    enum ConditionKind: Sendable {
        case onlyAfterSunset, onlyBeforeSunrise, onlyIfSomeoneIsHome, onlyIfNobodyIsHome, onlyBetweenTimes, onlyOnWeekdays, onlyIfDeviceIs
    }

    @Generable
    struct Condition: Sendable {
        var kind: ConditionKind
        @Guide(description: "24-hour start time, for onlyBetweenTimes. Night is 23:00.")
        var after: String?
        @Guide(description: "24-hour end time, for onlyBetweenTimes. Night ends at 06:00.")
        var before: String?
        @Guide(description: "Days among mon, tue, wed, thu, fri, sat, sun, for onlyOnWeekdays.")
        var days: [String]?
        @Guide(description: "A device id from the list, for onlyIfDeviceIs.")
        var deviceID: String?
        @Guide(description: "The state the device must be in, for onlyIfDeviceIs.")
        var state: String?
    }

    @Generable
    enum ActionKind: Sendable {
        case turnOn, turnOff, setPercent, openCover, closeCover, lockDoor, unlockDoor, setTemperature, activateScene, waitMinutes, sendNotification
    }

    @Generable
    struct Action: Sendable {
        var kind: ActionKind
        @Guide(description: "A device or scene id from the list. Not used by waitMinutes and sendNotification.")
        var deviceID: String?
        @Guide(description: "Brightness, position or speed in percent, for setPercent, or for turnOn when the request gives a level.")
        var percent: Int?
        @Guide(description: "Temperature in degrees, for setTemperature.")
        var temperature: Double?
        @Guide(description: "Minutes, for waitMinutes.")
        var minutes: Int?
        @Guide(description: "The notification text, for sendNotification.")
        var message: String?
    }
}

/// A device the model may use, as listed in its prompt.
struct RuleDevice: Sendable, Equatable {
    let id: String
    let name: String
    let kind: DeviceKind
    let area: String?

    var domain: String { String(id.split(separator: ".").first ?? "") }
}

/// What the request became: a rule to review, and what the person should know before saving it.
struct RuleProposal: Sendable {
    struct Note: Identifiable, Sendable {
        let id = UUID()
        let text: String
        /// Actions the note offers to add ("Add the Reading Lamp").
        var additions: [AutomationRule.Action] = []
        var additionTitle: String?
    }

    let request: String
    var rule: AutomationRule
    var notes: [Note]
    /// Parts of the request left out, in the request's words.
    var unsupported: [String]

    /// A rule needs something to start it and something to do.
    var isComplete: Bool { !rule.triggers.isEmpty && !rule.actions.isEmpty }
    /// Proposed as is only when nothing was left out; otherwise the person decides what to do.
    var needsHelp: Bool { !isComplete || !unsupported.isEmpty }
}

// MARK: - From draft to rule

extension RuleDraft {
    /// Keeps only what refers to real devices with values that make sense; everything else becomes a note.
    func proposal(for request: String, devices: [RuleDevice], notifyService: String?) -> RuleProposal {
        let byID = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rule = AutomationRule.new()
        var notes: [RuleProposal.Note] = []
        var unsupported = unsupported.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        rule.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trigger = trigger.ruleTrigger(byID) {
            rule.triggers = [trigger]
        }
        rule.conditions = conditions.compactMap { $0.ruleCondition(byID) }
        for action in actions {
            if let converted = action.ruleAction(byID, notifyService: notifyService) {
                if !rule.actions.contains(converted) { rule.actions.append(converted) }
            } else if let id = action.deviceID, byID[id] == nil {
                unsupported.append(String(localized: "A device called “\(id)”"))
            }
        }

        notes += Self.roomNotes(for: rule.actions, request: request, devices: devices)
        for case .device(let id, "lock.unlock", _) in rule.actions {
            notes.append(.init(text: String(localized: "This rule unlocks \(Phrasing.object(byID[id]?.name ?? id)) without you.")))
        }
        return RuleProposal(request: request, rule: rule, notes: notes, unsupported: unsupported)
    }

    /// "The living room": when the request names a room, or several of its lights are used,
    /// says which lights of that room were left out and offers to add them.
    private static func roomNotes(for actions: [AutomationRule.Action], request: String, devices: [RuleDevice]) -> [RuleProposal.Note] {
        let used = actions.compactMap { action -> (RuleDevice, AutomationRule.Action)? in
            guard case .device(let id, _, _) = action, let device = devices.first(where: { $0.id == id }), device.kind == .light else { return nil }
            return (device, action)
        }
        var notes: [RuleProposal.Note] = []
        for area in Set(used.compactMap(\.0.area)).sorted() {
            let inRoom = used.filter { $0.0.area == area }
            let named = request.localizedCaseInsensitiveContains(area)
            guard named || inRoom.count > 1 else { continue }
            let missing = devices.filter { $0.kind == .light && $0.area == area && !inRoom.map(\.0.id).contains($0.id) }
            guard !missing.isEmpty, case .device(_, let service, let data) = inRoom[0].1 else { continue }
            let included = inRoom.map(\.0.name).formatted(.list(type: .and))
            let left = missing.map(\.name).formatted(.list(type: .and))
            notes.append(.init(
                text: String(localized: "“\(area)”: this rule uses \(included), not \(left)."),
                additions: missing.map { .device(entityID: $0.id, service: service, data: data) },
                additionTitle: String(localized: "Add \(left)")
            ))
        }
        return notes
    }
}

extension RuleDraft.Trigger {
    func ruleTrigger(_ devices: [String: RuleDevice]) -> AutomationRule.Trigger? {
        switch kind {
        case .atTime: return time.flatMap(RuleDraft.clockTime).map { .time(at: $0) }
        case .atSunset: return .sun(.sunset, offset: offsetMinutes ?? 0)
        case .atSunrise: return .sun(.sunrise, offset: offsetMinutes ?? 0)
        case .whenEveryoneHasLeft: return .everyoneLeaves
        case .whenSomeoneArrivesHome: return .someoneArrives
        case .whenDeviceChanges:
            guard let id = deviceID, let device = devices[id] else { return nil }
            return .state(entityID: id, to: toState.map { RuleDraft.state($0, for: device) }, forMinutes: nil)
        case .whenValueRisesAbove, .whenValueFallsBelow:
            guard let id = deviceID, devices[id]?.kind == .sensor, let value else { return nil }
            return .threshold(entityID: id, above: kind == .whenValueRisesAbove ? value : nil, below: kind == .whenValueFallsBelow ? value : nil)
        }
    }
}

extension RuleDraft.Condition {
    func ruleCondition(_ devices: [String: RuleDevice]) -> AutomationRule.Condition? {
        switch kind {
        case .onlyAfterSunset: return .afterSunset
        case .onlyBeforeSunrise: return .beforeSunrise
        case .onlyIfSomeoneIsHome: return .someoneHome
        case .onlyIfNobodyIsHome: return .nobodyHome
        case .onlyBetweenTimes:
            guard let after = after.flatMap(RuleDraft.clockTime), let before = before.flatMap(RuleDraft.clockTime) else { return nil }
            return .between(after: after, before: before)
        case .onlyOnWeekdays:
            let valid = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
            let days = (days ?? []).map { String($0.lowercased().prefix(3)) }.filter(valid.contains)
            return days.isEmpty ? nil : .weekdays(valid.filter(days.contains))
        case .onlyIfDeviceIs:
            guard let id = deviceID, let device = devices[id], let state else { return nil }
            return .state(entityID: id, state: RuleDraft.state(state, for: device))
        }
    }
}

extension RuleDraft.Action {
    func ruleAction(_ devices: [String: RuleDevice], notifyService: String?) -> AutomationRule.Action? {
        switch kind {
        case .waitMinutes:
            guard let minutes, (1...720).contains(minutes) else { return nil }
            return .wait(minutes: minutes)
        case .sendNotification:
            guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty, let notifyService else { return nil }
            return .notify(service: notifyService, message: message)
        default:
            break
        }
        guard let id = deviceID, let device = devices[id] else { return nil }
        let domain = device.domain
        let level = percent.map { min(max($0, 1), 100) }
        switch (kind, device.kind) {
        case (.activateScene, .scene), (.turnOn, .scene):
            return .scene(entityID: id)
        case (.turnOn, .light):
            return .device(entityID: id, service: "light.turn_on", data: level.map { ["brightness_pct": .number(Double($0))] } ?? [:])
        case (.setPercent, .light):
            guard let level else { return nil }
            return .device(entityID: id, service: "light.turn_on", data: ["brightness_pct": .number(Double(level))])
        case (.setPercent, .cover):
            guard let percent else { return nil }
            return .device(entityID: id, service: "cover.set_cover_position", data: ["position": .number(Double(min(max(percent, 0), 100)))])
        case (.setPercent, .fan):
            guard let level else { return nil }
            return .device(entityID: id, service: "fan.set_percentage", data: ["percentage": .number(Double(level))])
        case (.openCover, .cover):
            return .device(entityID: id, service: "cover.open_cover", data: [:])
        case (.closeCover, .cover), (.turnOff, .cover):
            return .device(entityID: id, service: "cover.close_cover", data: [:])
        case (.lockDoor, .lock):
            return .device(entityID: id, service: "lock.lock", data: [:])
        case (.unlockDoor, .lock):
            return .device(entityID: id, service: "lock.unlock", data: [:])
        case (.setTemperature, .climate):
            guard let temperature, (5...35).contains(temperature) else { return nil }
            return .device(entityID: id, service: "climate.set_temperature", data: ["temperature": .number(temperature)])
        case (.turnOn, .switch), (.turnOn, .fan), (.turnOn, .mediaPlayer), (.turnOn, .climate), (.turnOn, .humidifier):
            return .device(entityID: id, service: "\(domain).turn_on", data: [:])
        case (.turnOff, .light), (.turnOff, .switch), (.turnOff, .fan), (.turnOff, .mediaPlayer), (.turnOff, .climate), (.turnOff, .humidifier):
            return .device(entityID: id, service: "\(domain).turn_off", data: [:])
        default:
            return nil
        }
    }
}

extension RuleDraft {
    /// "19:00", "7:5", "19 h" or "19h30" as Home Assistant's "19:00:00"; `nil` when it isn't a time of day.
    static func clockTime(_ text: String) -> String? {
        let parts = text.lowercased().split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let hour = parts.first, (0...23).contains(hour) else { return nil }
        let minute = parts.count > 1 ? parts[1] : 0
        guard (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d:00", hour, minute)
    }

    /// The state as Home Assistant names it for this kind of device ("open" is "on" for a door sensor).
    static func state(_ text: String, for device: RuleDevice) -> String {
        let state = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard device.kind == .binarySensor else { return state }
        switch state {
        case "open", "opened", "detected", "occupied", "wet": return "on"
        case "closed", "clear", "not_detected", "dry": return "off"
        default: return state
        }
    }
}
