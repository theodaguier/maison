import Foundation

/// A Home Assistant automation as the app edits it: WHEN (triggers), IF (conditions), THEN (actions).
///
/// Only the common shapes are understood. Anything else is kept verbatim as `.other`, so saving a
/// rule written in Home Assistant never loses what the app can't show.
struct AutomationRule: Equatable, Sendable {
    var id: String
    var name: String
    var description: String
    var triggers: [Trigger]
    var conditions: [Condition]
    var actions: [Action]
    /// Top-level keys the app doesn't edit (`mode`, `max`, `variables`…), written back unchanged.
    var extra: [String: JSONValue] = [:]

    enum SunEvent: String, Sendable, CaseIterable { case sunrise, sunset }

    enum Trigger: Equatable, Sendable {
        /// "19:00:00"
        case time(at: String)
        /// Offset in minutes, negative before the event.
        case sun(SunEvent, offset: Int)
        case state(entityID: String, to: String?, forMinutes: Int?)
        case threshold(entityID: String, above: Double?, below: Double?)
        case everyoneLeaves
        case someoneArrives
        case other(JSONValue)
    }

    enum Condition: Equatable, Sendable {
        case afterSunset
        case beforeSunrise
        case someoneHome
        case nobodyHome
        case between(after: String, before: String)
        case weekdays([String])
        case state(entityID: String, state: String)
        case other(JSONValue)
    }

    enum Action: Equatable, Sendable {
        /// `light.turn_on` on one entity, with its data (`brightness_pct`, `position`…).
        case device(entityID: String, service: String, data: [String: JSONValue])
        case scene(entityID: String)
        case wait(minutes: Int)
        case notify(service: String, message: String)
        case other(JSONValue)
    }

    static func new() -> AutomationRule {
        AutomationRule(
            id: String(Int(Date.now.timeIntervalSince1970 * 1000)),
            name: "",
            description: "",
            triggers: [],
            conditions: [],
            actions: [],
            extra: ["mode": "single"]
        )
    }
}

// MARK: - Reading

extension AutomationRule {
    init(id: String, config: JSONValue) {
        self.id = (config["id"]?.stringValue).flatMap { $0.isEmpty ? nil : $0 } ?? id
        name = config["alias"]?.stringValue ?? ""
        description = config["description"]?.stringValue ?? ""
        triggers = Self.list(config, "triggers", "trigger").map(Self.trigger)
        conditions = Self.list(config, "conditions", "condition").map(Self.condition)
        actions = Self.list(config, "actions", "action").map(Self.action)
        let known: Set = ["id", "alias", "description", "triggers", "trigger", "conditions", "condition", "actions", "action"]
        extra = (config.objectValue ?? [:]).filter { !known.contains($0.key) }
    }

    /// Accepts the current plural keys and the older singular ones, as a list or a single item.
    private static func list(_ config: JSONValue, _ plural: String, _ singular: String) -> [JSONValue] {
        guard let value = config[plural] ?? config[singular] else { return [] }
        return value.arrayValue ?? [value]
    }

    private static func entityID(_ value: JSONValue?) -> String? {
        value?.stringValue ?? value?.arrayValue?.first?.stringValue
    }

    private static func minutes(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        if let object = value.objectValue {
            let hours = object["hours"]?.doubleValue ?? 0
            let minutes = object["minutes"]?.doubleValue ?? 0
            let seconds = object["seconds"]?.doubleValue ?? 0
            return Int(hours * 60 + minutes + seconds / 60)
        }
        if let text = value.stringValue {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            if parts.count == 3 { return parts[0] * 60 + parts[1] + (parts[2] >= 30 ? 1 : 0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        return value.doubleValue.map { Int($0 / 60) }
    }

    private static func trigger(_ raw: JSONValue) -> Trigger {
        let kind = raw["trigger"]?.stringValue ?? raw["platform"]?.stringValue
        switch kind {
        case "time":
            if let at = raw["at"]?.stringValue, at.contains(":") { return .time(at: at) }
        case "sun":
            if let event = raw["event"]?.stringValue.flatMap(SunEvent.init(rawValue:)) {
                let offset = raw["offset"]?.stringValue.map { text -> Int in
                    let negative = text.hasPrefix("-")
                    let value = minutes(.string(negative ? String(text.dropFirst()) : text)) ?? 0
                    return negative ? -value : value
                } ?? 0
                return .sun(event, offset: offset)
            }
        case "state":
            if let id = entityID(raw["entity_id"]), raw["attribute"] == nil {
                return .state(entityID: id, to: raw["to"]?.stringValue, forMinutes: minutes(raw["for"]))
            }
        case "numeric_state":
            if let id = entityID(raw["entity_id"]), raw["attribute"] == nil, raw["value_template"] == nil {
                let above = raw["above"]?.doubleValue, below = raw["below"]?.doubleValue
                if id == "zone.home" {
                    if below == 1, above == nil { return .everyoneLeaves }
                    if above == 0, below == nil { return .someoneArrives }
                }
                if above != nil || below != nil { return .threshold(entityID: id, above: above, below: below) }
            }
        default:
            break
        }
        return .other(raw)
    }

    private static func condition(_ raw: JSONValue) -> Condition {
        switch raw["condition"]?.stringValue {
        case "sun":
            if raw["after"]?.stringValue == "sunset", raw["before"] == nil, raw["after_offset"] == nil { return .afterSunset }
            if raw["before"]?.stringValue == "sunrise", raw["after"] == nil, raw["before_offset"] == nil { return .beforeSunrise }
        case "numeric_state":
            if entityID(raw["entity_id"]) == "zone.home" {
                if raw["above"]?.doubleValue == 0, raw["below"] == nil { return .someoneHome }
                if raw["below"]?.doubleValue == 1, raw["above"] == nil { return .nobodyHome }
            }
        case "time":
            let weekdays = raw["weekday"].map { $0.arrayValue?.compactMap(\.stringValue) ?? [$0.stringValue].compactMap(\.self) }
            let after = raw["after"]?.stringValue, before = raw["before"]?.stringValue
            if let weekdays, after == nil, before == nil { return .weekdays(weekdays) }
            if let after, let before, weekdays == nil, after.contains(":"), before.contains(":") { return .between(after: after, before: before) }
        case "state":
            if let id = entityID(raw["entity_id"]), let state = raw["state"]?.stringValue, raw["attribute"] == nil, raw["for"] == nil {
                return .state(entityID: id, state: state)
            }
        default:
            break
        }
        return .other(raw)
    }

    private static func action(_ raw: JSONValue) -> Action {
        if let delay = raw["delay"], raw.objectValue?.count == 1, let minutes = minutes(delay) {
            return .wait(minutes: minutes)
        }
        guard let service = raw["action"]?.stringValue ?? raw["service"]?.stringValue else { return .other(raw) }
        let target = raw["target"]?["entity_id"] ?? raw["entity_id"] ?? raw["data"]?["entity_id"]
        let targetIDs = target.map { $0.arrayValue?.compactMap(\.stringValue) ?? [$0.stringValue].compactMap(\.self) } ?? []
        var data = raw["data"]?.objectValue ?? [:]
        data["entity_id"] = nil
        let hasOtherTargets = raw["target"]?["area_id"] != nil || raw["target"]?["device_id"] != nil || raw["target"]?["label_id"] != nil

        if service.hasPrefix("notify."), let message = data["message"]?.stringValue, targetIDs.isEmpty {
            return .notify(service: String(service.dropFirst("notify.".count)), message: message)
        }
        if service == "scene.turn_on", targetIDs.count == 1, data.isEmpty, !hasOtherTargets {
            return .scene(entityID: targetIDs[0])
        }
        if targetIDs.count == 1, !hasOtherTargets, raw["condition"] == nil, raw["enabled"] == nil, raw["continue_on_error"] == nil {
            return .device(entityID: targetIDs[0], service: service, data: data)
        }
        return .other(raw)
    }
}

// MARK: - Writing

extension AutomationRule {
    var config: JSONValue {
        var object = extra
        object["id"] = .string(id)
        object["alias"] = .string(name)
        object["description"] = .string(description)
        object["triggers"] = .array(triggers.map(\.json))
        object["conditions"] = .array(conditions.map(\.json))
        object["actions"] = .array(actions.map(\.json))
        return .object(object)
    }

    static func duration(minutes: Int) -> JSONValue {
        ["hours": .number(Double(minutes / 60)), "minutes": .number(Double(minutes % 60)), "seconds": 0]
    }
}

extension AutomationRule.Trigger {
    var json: JSONValue {
        switch self {
        case .time(let at):
            return ["trigger": "time", "at": .string(at)]
        case .sun(let event, let offset):
            var object: [String: JSONValue] = ["trigger": "sun", "event": .string(event.rawValue)]
            if offset != 0 {
                let minutes = abs(offset)
                object["offset"] = .string((offset < 0 ? "-" : "") + String(format: "%02d:%02d:00", minutes / 60, minutes % 60))
            }
            return .object(object)
        case .state(let entityID, let to, let forMinutes):
            var object: [String: JSONValue] = ["trigger": "state", "entity_id": .string(entityID)]
            if let to { object["to"] = .string(to) }
            if let forMinutes, forMinutes > 0 { object["for"] = AutomationRule.duration(minutes: forMinutes) }
            return .object(object)
        case .threshold(let entityID, let above, let below):
            var object: [String: JSONValue] = ["trigger": "numeric_state", "entity_id": .string(entityID)]
            if let above { object["above"] = .number(above) }
            if let below { object["below"] = .number(below) }
            return .object(object)
        case .everyoneLeaves:
            return ["trigger": "numeric_state", "entity_id": "zone.home", "below": 1]
        case .someoneArrives:
            return ["trigger": "numeric_state", "entity_id": "zone.home", "above": 0]
        case .other(let raw):
            return raw
        }
    }
}

extension AutomationRule.Condition {
    var json: JSONValue {
        switch self {
        case .afterSunset: ["condition": "sun", "after": "sunset"]
        case .beforeSunrise: ["condition": "sun", "before": "sunrise"]
        case .someoneHome: ["condition": "numeric_state", "entity_id": "zone.home", "above": 0]
        case .nobodyHome: ["condition": "numeric_state", "entity_id": "zone.home", "below": 1]
        case .between(let after, let before): ["condition": "time", "after": .string(after), "before": .string(before)]
        case .weekdays(let days): ["condition": "time", "weekday": .array(days.map { .string($0) })]
        case .state(let entityID, let state): ["condition": "state", "entity_id": .string(entityID), "state": .string(state)]
        case .other(let raw): raw
        }
    }
}

extension AutomationRule.Action {
    var json: JSONValue {
        switch self {
        case .device(let entityID, let service, let data):
            var object: [String: JSONValue] = ["action": .string(service), "target": ["entity_id": .string(entityID)]]
            if !data.isEmpty { object["data"] = .object(data) }
            return .object(object)
        case .scene(let entityID):
            return ["action": "scene.turn_on", "target": ["entity_id": .string(entityID)]]
        case .wait(let minutes):
            return ["delay": AutomationRule.duration(minutes: minutes)]
        case .notify(let service, let message):
            return ["action": .string("notify.\(service)"), "data": ["message": .string(message)]]
        case .other(let raw):
            return raw
        }
    }
}

// MARK: - Runs

/// One run of an automation, from its stored traces.
struct AutomationRun: Sendable, Hashable {
    let automationID: String
    let start: Date
    /// `finished`, `error`, `failed_conditions`, `cancelled`…
    let execution: String

    /// Stopped by its own conditions: the rule was checked but didn't run.
    var didRun: Bool { execution != "failed_conditions" && execution != "failed_single" }
    var failed: Bool { execution == "error" }
}

extension HomeAssistantConnection {
    func automationRuns() async throws -> [AutomationRun] {
        let result = try await send(["type": "trace/list", "domain": "automation"])
        return (result.arrayValue ?? []).compactMap { trace in
            guard let item = trace["item_id"]?.stringValue,
                  let start = trace["timestamp"]?["start"]?.stringValue.flatMap(EntityState.parseDate) else { return nil }
            return AutomationRun(automationID: item, start: start, execution: trace["script_execution"]?.stringValue ?? "finished")
        }
    }
}
