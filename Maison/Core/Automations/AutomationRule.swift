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
        /// Every N minutes; whole hours are written as an hour pattern.
        case every(minutes: Int)
        /// Start or end of an event in a calendar, with an offset in minutes, negative before.
        case calendar(entityID: String, start: Bool, offset: Int)
        /// One person enters or leaves home.
        case person(entityID: String, arrives: Bool)
        /// An NFC tag registered in Home Assistant is scanned.
        case tag(id: String)
        case serverStarts
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
        /// The sun is above the horizon.
        case daytime
        /// The sun is below the horizon.
        case nighttime
        case person(entityID: String, isHome: Bool)
        case threshold(entityID: String, above: Double?, below: Double?)
        case other(JSONValue)
    }

    enum Action: Equatable, Sendable {
        /// `light.turn_on` on one entity, with its data (`brightness_pct`, `position`…).
        case device(entityID: String, service: String, data: [String: JSONValue])
        case scene(entityID: String)
        case wait(minutes: Int)
        case notify(service: String, message: String)
        /// Every light of a room, or of the whole home when `areaID` is nil.
        case lights(areaID: String?, on: Bool)
        case script(entityID: String)
        /// Runs, turns on or turns off another rule.
        case rule(entityID: String, command: RuleCommand)
        case other(JSONValue)
    }

    enum RuleCommand: String, Sendable, CaseIterable { case trigger, turnOn = "turn_on", turnOff = "turn_off" }

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

    /// "-00:15:00" or "00:15:00" as signed minutes.
    private static func signedMinutes(_ value: JSONValue?) -> Int? {
        guard let text = value?.stringValue else { return value.flatMap(minutes) }
        let negative = text.hasPrefix("-")
        let value = minutes(.string(negative ? String(text.dropFirst()) : text)) ?? 0
        return negative ? -value : value
    }

    static func signedDuration(_ offset: Int) -> JSONValue {
        let minutes = abs(offset)
        return .string((offset < 0 ? "-" : "") + String(format: "%02d:%02d:00", minutes / 60, minutes % 60))
    }

    private static func trigger(_ raw: JSONValue) -> Trigger {
        let kind = raw["trigger"]?.stringValue ?? raw["platform"]?.stringValue
        switch kind {
        case "time_pattern":
            let pattern = { (key: String) -> String? in raw[key].map { $0.stringValue ?? $0.doubleValue.map { String(Int($0)) } ?? "" } }
            let hours = pattern("hours"), minutes = pattern("minutes"), seconds = pattern("seconds")
            if seconds == nil || seconds == "0" {
                if hours == nil, let minutes, minutes.hasPrefix("/"), let n = Int(minutes.dropFirst()), n > 0 { return .every(minutes: n) }
                if let hours, hours.hasPrefix("/"), let n = Int(hours.dropFirst()), n > 0, minutes == "0" { return .every(minutes: n * 60) }
            }
        case "calendar":
            if let id = entityID(raw["entity_id"]), let event = raw["event"]?.stringValue, event == "start" || event == "end" {
                return .calendar(entityID: id, start: event == "start", offset: signedMinutes(raw["offset"]) ?? 0)
            }
        case "zone":
            if let id = entityID(raw["entity_id"]), id.hasPrefix("person."), raw["zone"]?.stringValue == "zone.home",
               let event = raw["event"]?.stringValue, event == "enter" || event == "leave" {
                return .person(entityID: id, arrives: event == "enter")
            }
        case "tag":
            if let id = raw["tag_id"]?.stringValue, raw["device_id"] == nil { return .tag(id: id) }
        case "homeassistant":
            if raw["event"]?.stringValue == "start" { return .serverStarts }
        case "time":
            if let at = raw["at"]?.stringValue, at.contains(":") { return .time(at: at) }
        case "sun":
            if let event = raw["event"]?.stringValue.flatMap(SunEvent.init(rawValue:)) {
                return .sun(event, offset: signedMinutes(raw["offset"]) ?? 0)
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
            } else if let id = entityID(raw["entity_id"]), raw["attribute"] == nil, raw["value_template"] == nil {
                let above = raw["above"]?.doubleValue, below = raw["below"]?.doubleValue
                if above != nil || below != nil { return .threshold(entityID: id, above: above, below: below) }
            }
        case "time":
            let weekdays = raw["weekday"].map { $0.arrayValue?.compactMap(\.stringValue) ?? [$0.stringValue].compactMap { $0 } }
            let after = raw["after"]?.stringValue, before = raw["before"]?.stringValue
            if let weekdays, after == nil, before == nil { return .weekdays(weekdays) }
            if let after, let before, weekdays == nil, after.contains(":"), before.contains(":") { return .between(after: after, before: before) }
        case "state":
            if let id = entityID(raw["entity_id"]), let state = raw["state"]?.stringValue, raw["attribute"] == nil, raw["for"] == nil {
                switch (id, state) {
                case ("sun.sun", "above_horizon"): return .daytime
                case ("sun.sun", "below_horizon"): return .nighttime
                case (_, "home") where id.hasPrefix("person."): return .person(entityID: id, isHome: true)
                case (_, "not_home") where id.hasPrefix("person."): return .person(entityID: id, isHome: false)
                default: return .state(entityID: id, state: state)
                }
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
        let targetIDs = target.map { $0.arrayValue?.compactMap(\.stringValue) ?? [$0.stringValue].compactMap { $0 } } ?? []
        var data = raw["data"]?.objectValue ?? [:]
        data["entity_id"] = nil
        let hasOtherTargets = raw["target"]?["area_id"] != nil || raw["target"]?["device_id"] != nil || raw["target"]?["label_id"] != nil

        if service.hasPrefix("notify."), let message = data["message"]?.stringValue, targetIDs.isEmpty {
            return .notify(service: String(service.dropFirst("notify.".count)), message: message)
        }
        if service == "scene.turn_on", targetIDs.count == 1, data.isEmpty, !hasOtherTargets {
            return .scene(entityID: targetIDs[0])
        }
        if service == "light.turn_on" || service == "light.turn_off", data.isEmpty, raw["target"]?["device_id"] == nil, raw["target"]?["label_id"] == nil {
            let on = service == "light.turn_on"
            let areas = raw["target"]?["area_id"].map { $0.arrayValue?.compactMap(\.stringValue) ?? [$0.stringValue].compactMap { $0 } } ?? []
            if targetIDs == ["all"], areas.isEmpty { return .lights(areaID: nil, on: on) }
            if targetIDs.isEmpty, areas.count == 1 { return .lights(areaID: areas[0], on: on) }
        }
        if service == "script.turn_on", targetIDs.count == 1, targetIDs[0].hasPrefix("script."), data.isEmpty, !hasOtherTargets {
            return .script(entityID: targetIDs[0])
        }
        if service.hasPrefix("automation."), let command = RuleCommand(rawValue: String(service.dropFirst("automation.".count))),
           targetIDs.count == 1, data.isEmpty, !hasOtherTargets {
            return .rule(entityID: targetIDs[0], command: command)
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
            if offset != 0 { object["offset"] = AutomationRule.signedDuration(offset) }
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
        case .every(let minutes):
            if minutes >= 60, minutes % 60 == 0 { return ["trigger": "time_pattern", "hours": .string("/\(minutes / 60)"), "minutes": "0"] }
            return ["trigger": "time_pattern", "minutes": .string("/\(minutes)")]
        case .calendar(let entityID, let start, let offset):
            var object: [String: JSONValue] = ["trigger": "calendar", "entity_id": .string(entityID), "event": start ? "start" : "end"]
            if offset != 0 { object["offset"] = AutomationRule.signedDuration(offset) }
            return .object(object)
        case .person(let entityID, let arrives):
            return ["trigger": "zone", "entity_id": .string(entityID), "zone": "zone.home", "event": arrives ? "enter" : "leave"]
        case .tag(let id):
            return ["trigger": "tag", "tag_id": .string(id)]
        case .serverStarts:
            return ["trigger": "homeassistant", "event": "start"]
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
        case .daytime: ["condition": "state", "entity_id": "sun.sun", "state": "above_horizon"]
        case .nighttime: ["condition": "state", "entity_id": "sun.sun", "state": "below_horizon"]
        case .person(let entityID, let isHome): ["condition": "state", "entity_id": .string(entityID), "state": isHome ? "home" : "not_home"]
        case .threshold(let entityID, let above, let below):
            .object(["condition": "numeric_state", "entity_id": .string(entityID), "above": above.map { .number($0) }, "below": below.map { .number($0) }]
                .compactMapValues { $0 })
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
        case .lights(let areaID, let on):
            let target: JSONValue = areaID.map { ["area_id": .string($0)] } ?? ["entity_id": "all"]
            return ["action": on ? "light.turn_on" : "light.turn_off", "target": target]
        case .script(let entityID):
            return ["action": "script.turn_on", "target": ["entity_id": .string(entityID)]]
        case .rule(let entityID, let command):
            return ["action": .string("automation.\(command.rawValue)"), "target": ["entity_id": .string(entityID)]]
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
