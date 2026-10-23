import SwiftUI

/// How a step of a rule reads in a list: icon, colour, title and detail.
struct StepDescription {
    let symbol: String
    let color: Color
    let title: String
    var detail: String?
}

extension HomeStore {
    func entityName(_ id: String) -> String {
        states[id]?.name ?? id
    }

    func describe(_ trigger: AutomationRule.Trigger) -> StepDescription {
        switch trigger {
        case .time(let at):
            return StepDescription(symbol: "clock.fill", color: .blue,
                                   title: String(localized: "Every day at \(RuleTime.display(at))"),
                                   detail: String(localized: "Fixed time"))
        case .sun(let event, let offset):
            return StepDescription(symbol: event == .sunset ? "sunset.fill" : "sunrise.fill", color: .orange,
                                   title: RuleTime.sunText(event, offset: offset), detail: String(localized: "Sun"))
        case .state(let id, let to, let forMinutes):
            let name = entityName(id)
            var title = to.map { String(localized: "\(name) becomes \(stateName($0, of: id))") } ?? String(localized: "\(name) changes")
            if let forMinutes, forMinutes > 0 { title += " " + String(localized: "for \(forMinutes) min") }
            return StepDescription(symbol: states[id]?.symbolName ?? "sensor.fill", color: .teal, title: title,
                                   detail: area(of: states[id])?.name ?? String(localized: "Device"))
        case .threshold(let id, let above, let below):
            let unit = states[id]?.unit ?? ""
            let title = if let above {
                String(localized: "\(entityName(id)) above \(Self.number(above))\(unit)")
            } else {
                String(localized: "\(entityName(id)) below \(Self.number(below ?? 0))\(unit)")
            }
            return StepDescription(symbol: "thermometer.medium", color: .orange, title: title,
                                   detail: area(of: states[id])?.name ?? String(localized: "Measurement"))
        case .everyoneLeaves:
            return StepDescription(symbol: "figure.walk.departure", color: .indigo, title: String(localized: "When everyone leaves"),
                                   detail: String(localized: "Household members"))
        case .someoneArrives:
            return StepDescription(symbol: "figure.walk.arrival", color: .indigo, title: String(localized: "When someone arrives"),
                                   detail: String(localized: "Household members"))
        case .other(let raw):
            return StepDescription(symbol: "gearshape.fill", color: .gray,
                                   title: String(localized: "Trigger set up in Home Assistant"),
                                   detail: raw["trigger"]?.stringValue ?? raw["platform"]?.stringValue)
        }
    }

    func describe(_ condition: AutomationRule.Condition) -> StepDescription {
        switch condition {
        case .afterSunset:
            StepDescription(symbol: "sunset.fill", color: .purple, title: String(localized: "After sunset"))
        case .beforeSunrise:
            StepDescription(symbol: "sunrise.fill", color: .purple, title: String(localized: "Before sunrise"))
        case .someoneHome:
            StepDescription(symbol: "person.2.fill", color: .purple, title: String(localized: "Someone is home"),
                            detail: String(localized: "Household members"))
        case .nobodyHome:
            StepDescription(symbol: "person.2.slash.fill", color: .purple, title: String(localized: "Nobody is home"),
                            detail: String(localized: "Household members"))
        case .between(let after, let before):
            StepDescription(symbol: "clock.fill", color: .purple,
                            title: String(localized: "Between \(RuleTime.display(after)) and \(RuleTime.display(before))"))
        case .weekdays(let days):
            StepDescription(symbol: "calendar", color: .purple, title: RuleTime.weekdaysText(days))
        case .state(let id, let state):
            StepDescription(symbol: states[id]?.symbolName ?? "sensor.fill", color: .purple,
                            title: String(localized: "\(entityName(id)) is \(stateName(state, of: id))"),
                            detail: area(of: states[id])?.name)
        case .other(let raw):
            StepDescription(symbol: "gearshape.fill", color: .gray, title: String(localized: "Condition set up in Home Assistant"),
                            detail: raw["condition"]?.stringValue)
        }
    }

    func describe(_ action: AutomationRule.Action) -> StepDescription {
        switch action {
        case .device(let id, let service, let data):
            let entity = states[id]
            return StepDescription(symbol: entity?.symbolName ?? "switch.2", color: entity?.accent ?? .orange,
                                   title: entityName(id), detail: commandText(service, data: data))
        case .scene(let id):
            return StepDescription(symbol: "play.fill", color: .orange, title: entityName(id), detail: String(localized: "Run the scene"))
        case .wait(let minutes):
            return StepDescription(symbol: "hourglass", color: .orange, title: String(localized: "Wait \(minutes) min"))
        case .notify(_, let message):
            return StepDescription(symbol: "bell.fill", color: .red, title: String(localized: "Send a notification"), detail: message)
        case .other(let raw):
            return StepDescription(symbol: "gearshape.fill", color: .gray, title: String(localized: "Action set up in Home Assistant"),
                                   detail: raw["action"]?.stringValue ?? raw["service"]?.stringValue)
        }
    }

    /// "Turn on · 60 % · warm white", "Close", "Set to 21°"
    func commandText(_ service: String, data: [String: JSONValue]) -> String {
        let verb = String(service.split(separator: ".").last ?? "")
        var parts: [String] = []
        switch verb {
        case "turn_on": parts.append(String(localized: "Turn on"))
        case "turn_off": parts.append(String(localized: "Turn off"))
        case "toggle": parts.append(String(localized: "Toggle"))
        case "open_cover": parts.append(String(localized: "action.open", defaultValue: "Open"))
        case "close_cover": parts.append(String(localized: "Close"))
        case "set_cover_position": parts.append(String(localized: "Position \(Self.number(data["position"]?.doubleValue ?? 0)) %"))
        case "lock": parts.append(String(localized: "Lock"))
        case "unlock": parts.append(String(localized: "Unlock"))
        case "set_temperature": parts.append(String(localized: "Set to \(EntityState.degrees(data["temperature"]?.doubleValue ?? 0))"))
        case "media_play": parts.append(String(localized: "Play"))
        case "media_pause": parts.append(String(localized: "Pause"))
        default: parts.append(verb.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let brightness = data["brightness_pct"]?.doubleValue { parts.append("\(Self.number(brightness)) %") }
        if let kelvin = data["color_temp_kelvin"]?.doubleValue { parts.append(RuleTime.whiteName(kelvin)) }
        return parts.joined(separator: ", ")
    }

    /// One line saying what a rule does: its description, or a summary of its actions.
    func summary(of rule: AutomationRule) -> String {
        if !rule.description.isEmpty { return rule.description }
        var phrases: [String] = []
        var actions = rule.actions
        // "Turn on, wait, turn off" on the same device reads as "turns on X for 2 min".
        var index = 0
        while index + 2 < actions.count {
            if case .device(let id, let on, let data) = actions[index], on.hasSuffix(".turn_on"),
               case .wait(let minutes) = actions[index + 1],
               case .device(id, let off, _) = actions[index + 2], off.hasSuffix(".turn_off") {
                var phrase = String(localized: "turns on \(Phrasing.object(entityName(id))) for \(minutes) min")
                if let brightness = data["brightness_pct"]?.doubleValue { phrase += " " + String(localized: "at \(Self.number(brightness)) %") }
                phrases.append(phrase)
                actions.removeSubrange(index...(index + 2))
            } else {
                index += 1
            }
        }
        let devices = actions.compactMap { action -> (id: String, service: String, data: [String: JSONValue])? in
            if case .device(let id, let service, let data) = action { return (id, service, data) }
            return nil
        }
        let lightsOn = devices.filter { $0.service == "light.turn_on" }
        let lightsOff = devices.filter { $0.service == "light.turn_off" }
        if !lightsOn.isEmpty {
            let rooms = Set(lightsOn.compactMap { area(of: states[$0.id])?.name })
            let brightness = lightsOn.first?.data["brightness_pct"]?.doubleValue
            var phrase = lightsOn.count == 1
                ? String(localized: "turns on \(Phrasing.object(entityName(lightsOn[0].id)))")
                : String(localized: "turns on \(lightsOn.count) lights")
            if lightsOn.count > 1, rooms.count == 1, let room = rooms.first { phrase += " " + Phrasing.location(room) }
            if let brightness { phrase += " " + String(localized: "at \(Self.number(brightness)) %") }
            phrases.append(phrase)
        }
        if !lightsOff.isEmpty {
            let allLights = devices.isEmpty ? 0 : self.devices.filter { $0.kind == .light }.count
            phrases.append(lightsOff.count >= allLights && allLights > 1
                ? String(localized: "turns off all the lights")
                : lightsOff.count == 1 ? String(localized: "turns off \(Phrasing.object(entityName(lightsOff[0].id)))")
                : String(localized: "turns off \(lightsOff.count) lights"))
        }
        for device in devices where !device.service.hasPrefix("light.") {
            let name = Phrasing.object(entityName(device.id))
            switch device.service {
            case "cover.close_cover": phrases.append(String(localized: "closes \(name)"))
            case "cover.open_cover": phrases.append(String(localized: "opens \(name)"))
            case "lock.lock": phrases.append(String(localized: "locks \(name)"))
            case "lock.unlock": phrases.append(String(localized: "unlocks \(name)"))
            case let service where service.hasSuffix(".turn_off"): phrases.append(String(localized: "turns off \(name)"))
            case let service where service.hasSuffix(".turn_on"): phrases.append(String(localized: "turns on \(name)"))
            default: phrases.append(String(localized: "controls \(name)"))
            }
        }
        for action in actions {
            if case .scene(let id) = action { phrases.append(String(localized: "runs “\(entityName(id))”")) }
            if case .notify = action { phrases.append(String(localized: "sends a notification")) }
        }
        let text = phrases.formatted(.list(type: .and))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    func stateName(_ state: String, of id: String) -> String {
        guard let entity = states[id] else { return state }
        return EntityState(entityID: id, state: state, attributes: entity.attributes).stateLabel.lowercased()
    }

    private func area(of entity: EntityState?) -> Area? {
        entity.flatMap { area(of: $0) }
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Times as rules store them ("19:00:00") and as people read them.
enum RuleTime {
    static func date(_ text: String) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 0, minute: parts.dropFirst().first ?? 0, second: 0, of: .now) ?? .now
    }

    static func text(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func display(_ text: String) -> String {
        date(text).formatted(date: .omitted, time: .shortened)
    }

    static func sunText(_ event: AutomationRule.SunEvent, offset: Int) -> String {
        switch (event, offset) {
        case (.sunset, 0): String(localized: "At sunset")
        case (.sunrise, 0): String(localized: "At sunrise")
        case (.sunset, ..<0): String(localized: "\(-offset) min before sunset")
        case (.sunrise, ..<0): String(localized: "\(-offset) min before sunrise")
        case (.sunset, _): String(localized: "\(offset) min after sunset")
        case (.sunrise, _): String(localized: "\(offset) min after sunrise")
        }
    }

    static let weekdayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    static func weekdaySymbol(_ key: String) -> String {
        // Calendar's symbols start on Sunday.
        guard let index = weekdayKeys.firstIndex(of: key) else { return key }
        return Calendar.current.shortWeekdaySymbols[(index + 1) % 7]
    }

    static func weekdaysText(_ days: [String]) -> String {
        let ordered = weekdayKeys.filter(days.contains)
        if ordered == ["mon", "tue", "wed", "thu", "fri"] { return String(localized: "On weekdays") }
        if ordered == ["sat", "sun"] { return String(localized: "On weekends") }
        return ordered.map(weekdaySymbol).formatted(.list(type: .and))
    }

    static func whiteName(_ kelvin: Double) -> String {
        switch kelvin {
        case ..<3200: String(localized: "warm white")
        case ..<4500: String(localized: "neutral white")
        default: String(localized: "cool white")
        }
    }
}
