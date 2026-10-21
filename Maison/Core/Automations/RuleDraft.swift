import Foundation
import FoundationModels

/// What a request means, as the on-device model reads it. The model never sees the devices: it names
/// them with the request's own words, and `RuleDraft.proposal` finds them in the home. Numbers that
/// aren't in the request are dropped there too.
@Generable
struct RuleDraft: Sendable {
    @Guide(description: "The words of the request that say when the rule starts, copied as they are.")
    var whenWords: String

    var trigger: Trigger

    @Guide(description: "True when the request limits the rule to the night.")
    var onlyAtNight: Bool
    @Guide(description: "True when the request says the sun must have set.")
    var onlyAfterSunset: Bool
    @Guide(description: "True when the request says someone must be home.")
    var onlyIfSomeoneIsHome: Bool
    @Guide(description: "True when the request says nobody must be home.")
    var onlyIfNobodyIsHome: Bool
    @Guide(description: "True when the request limits the rule to weekdays.")
    var onlyOnWeekdays: Bool
    @Guide(description: "True when the request limits the rule to the weekend.")
    var onlyOnWeekend: Bool

    @Guide(description: "What to do, in order.")
    var actions: [Action]

    @Guide(description: "Parts of the request that no kind expresses, copied word for word. Usually empty.")
    var unsupported: [String]

    @Guide(description: "A short name for the rule, two to four words, in the request's language.")
    var name: String

    @Generable
    enum TriggerKind: Sendable {
        case motionDetected, doorOrWindowOpens, doorOrWindowCloses, deviceTurnsOn, deviceTurnsOff
        case temperatureRisesAbove, temperatureFallsBelow, humidityRisesAbove
        case everyoneHasLeft, someoneArrivesHome, sunset, sunrise, fixedTime
    }

    @Generable
    struct Trigger: Sendable {
        var kind: TriggerKind
        @Guide(description: "Words of the request naming the room or device watched, if any.")
        var place: String?
        @Guide(description: "24-hour time such as 19:00, for fixedTime.")
        var time: String?
        @Guide(description: "The threshold, for temperature and humidity.")
        var value: Double?
    }

    @Generable
    enum ActionKind: Sendable {
        case turnOn, turnOff, setBrightness, openBlinds, closeBlinds, lock, unlock, setTemperature, wait, notifyMe
    }

    @Generable
    struct Action: Sendable {
        var kind: ActionKind
        @Guide(description: "Words of the request naming what to act on, such as “le salon”, “les volets”, “la clim” or “tout”.")
        var target: String?
        @Guide(description: "Percent, for setBrightness, or for turnOn when the request gives a level.")
        var percent: Int?
        @Guide(description: "Degrees, for setTemperature.")
        var temperature: Double?
        @Guide(description: "Minutes, for wait.")
        var minutes: Int?
        @Guide(description: "Text, for notifyMe.")
        var message: String?
    }

    static let instructions = """
    You read a request for a home automation rule and say what it means. You don't know the devices: \
    name them with the request's own words.
    The trigger is the event the rule waits for. A time of day ("la nuit", "le soir") together with an event is a condition, not the trigger.
    "Ferme" means closeBlinds for blinds, "ouvre" openBlinds. "Coupe" means turnOff.
    """
}

/// A device a rule may use.
struct RuleDevice: Sendable, Equatable {
    let id: String
    let name: String
    let kind: DeviceKind
    var deviceClass: String?
    var area: String?

    var domain: String { String(id.split(separator: ".").first ?? "") }
}

/// What the request became: a rule to review, and what the person should know before saving it.
struct RuleProposal: Sendable {
    let request: String
    var rule: AutomationRule
    /// Things to check, such as which lights "the living room" stands for.
    var notes: [String]
    /// Parts of the request left out, in its words.
    var unsupported: [String]
    /// Words that named no device of the home ("le lave-linge").
    var unmatched: [String] = []

    /// A rule needs something to start it and something to do.
    var isComplete: Bool { !rule.triggers.isEmpty && !rule.actions.isEmpty }
    /// Proposed as is only when nothing was left out; otherwise the person decides what to do next.
    var needsHelp: Bool { !isComplete || !unsupported.isEmpty || !unmatched.isEmpty }
}

// MARK: - From draft to rule

extension RuleDraft {
    func proposal(for request: String, devices: [RuleDevice], notifyService: String?) -> RuleProposal {
        var rule = AutomationRule.new()
        var notes: [String] = []
        let requestWords = RuleWords(request)
        var unsupported = unsupported.filter { !$0.isEmpty && requestWords.contains(phrase: $0) }
        var unmatched: [String] = []
        let numbers = GroundedNumbers.numbers(in: request, locale: .current)
        func grounded(_ value: Double?) -> Double? { value.flatMap { numbers.contains(Int($0)) ? $0 : nil } }
        func grounded(_ value: Int?) -> Int? { value.flatMap { numbers.contains($0) ? $0 : nil } }

        // Actions first: when the trigger names no place, the devices acted on tell where to look.
        for action in actions {
            let found = RuleDevice.matching(action.target, for: action.kind, in: devices)
            if found.devices.isEmpty, ![.wait, .notifyMe].contains(action.kind) {
                if let target = action.target, !target.isEmpty { unmatched.append(target) }
                continue
            }
            if found.devices.count > 1, found.byPlace, let target = action.target {
                notes.append(String(localized: "“\(target)” stands for \(found.devices.map(\.name).formatted(.list(type: .and)))."))
            }
            let converted = action.ruleActions(for: found.devices, request: request,
                                               percent: grounded(action.percent), temperature: grounded(action.temperature),
                                               minutes: grounded(action.minutes), notifyService: notifyService)
            for item in converted where !rule.actions.contains(item) { rule.actions.append(item) }
        }
        let actedAreas = Set(rule.actions.compactMap { action -> String? in
            guard case .device(let id, _, _) = action else { return nil }
            return devices.first { $0.id == id }?.area
        })

        if let trigger = trigger.ruleTrigger(whenWords: whenWords, devices: devices, nearAreas: actedAreas, value: grounded(trigger.value)) {
            rule.triggers = [trigger]
        } else {
            unsupported.insert(whenWords, at: 0)
        }

        if onlyAtNight { rule.conditions.append(.between(after: "23:00:00", before: "06:00:00")) }
        if onlyAfterSunset, !rule.triggers.contains(.sun(.sunset, offset: 0)) { rule.conditions.append(.afterSunset) }
        if onlyIfSomeoneIsHome { rule.conditions.append(.someoneHome) }
        if onlyIfNobodyIsHome { rule.conditions.append(.nobodyHome) }
        if onlyOnWeekdays { rule.conditions.append(.weekdays(["mon", "tue", "wed", "thu", "fri"])) }
        if onlyOnWeekend { rule.conditions.append(.weekdays(["sat", "sun"])) }

        for case .device(let id, "lock.unlock", _) in rule.actions {
            notes.append(String(localized: "This rule unlocks \(Phrasing.object(devices.first { $0.id == id }?.name ?? id)) on its own."))
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.name = name.prefix(1).uppercased() + name.dropFirst()
        return RuleProposal(request: request, rule: rule, notes: notes, unsupported: unsupported, unmatched: unmatched)
    }
}

extension RuleDraft.Trigger {
    func ruleTrigger(whenWords: String, devices: [RuleDevice], nearAreas: Set<String>, value: Double?) -> AutomationRule.Trigger? {
        // "Le soir à 19 h, si le soleil est couché": a time given with the sun is a fixed time.
        let givenTime = time.flatMap { RuleDraft.clockTime($0) } ?? RuleDraft.timeInSentence(whenWords)
        switch kind {
        case .fixedTime:
            return givenTime.map { .time(at: $0) }
        case .sunset, .sunrise:
            if let givenTime { return .time(at: givenTime) }
            return .sun(kind == .sunset ? .sunset : .sunrise, offset: 0)
        case .everyoneHasLeft: return .everyoneLeaves
        case .someoneArrivesHome: return .someoneArrives
        case .motionDetected, .doorOrWindowOpens, .doorOrWindowCloses:
            let classes = kind == .motionDetected ? ["motion", "occupancy", "presence"] : ["door", "window", "opening", "garage_door"]
            let sensors = devices.filter { $0.kind == .binarySensor && classes.contains($0.deviceClass ?? "") }
            guard let sensor = RuleDevice.watched(place, among: sensors, nearAreas: nearAreas) else { return nil }
            return .state(entityID: sensor.id, to: kind == .doorOrWindowCloses ? "off" : "on", forMinutes: nil)
        case .deviceTurnsOn, .deviceTurnsOff:
            let watched = devices.filter { $0.kind != .scene }
            guard let place, let device = RuleDevice.watched(place, among: watched, nearAreas: []) else { return nil }
            return .state(entityID: device.id, to: kind == .deviceTurnsOn ? "on" : "off", forMinutes: nil)
        case .temperatureRisesAbove, .temperatureFallsBelow, .humidityRisesAbove:
            let deviceClass = kind == .humidityRisesAbove ? "humidity" : "temperature"
            let sensors = devices.filter { $0.kind == .sensor && $0.deviceClass == deviceClass }
            guard let value, let sensor = RuleDevice.watched(place, among: sensors, nearAreas: nearAreas) else { return nil }
            return .threshold(entityID: sensor.id, above: kind == .temperatureFallsBelow ? nil : value,
                              below: kind == .temperatureFallsBelow ? value : nil)
        }
    }
}

extension RuleDraft.Action {
    func ruleActions(for devices: [RuleDevice], request: String, percent: Int?, temperature: Double?, minutes: Int?,
                     notifyService: String?) -> [AutomationRule.Action] {
        switch kind {
        case .wait:
            guard let minutes, (1...720).contains(minutes) else { return [] }
            return [.wait(minutes: minutes)]
        case .notifyMe:
            guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty, let notifyService else { return [] }
            return [.notify(service: notifyService, message: message)]
        default:
            return devices.compactMap { action(on: $0, request: request, percent: percent, temperature: temperature) }
        }
    }

    private func action(on device: RuleDevice, request: String, percent: Int?, temperature: Double?) -> AutomationRule.Action? {
        let level = percent.map { min(max($0, 1), 100) }
        switch (kind, device.kind) {
        case (.turnOn, .scene):
            return .scene(entityID: device.id)
        case (.turnOn, .light), (.setBrightness, .light):
            var data: [String: JSONValue] = [:]
            if let level { data["brightness_pct"] = .number(Double(level)) }
            if let kelvin = RuleWords(request).colorTemperature { data["color_temp_kelvin"] = .number(kelvin) }
            if kind == .setBrightness, level == nil { return nil }
            return .device(entityID: device.id, service: "light.turn_on", data: data)
        case (.setBrightness, .cover):
            guard let percent else { return nil }
            return .device(entityID: device.id, service: "cover.set_cover_position", data: ["position": .number(Double(min(max(percent, 0), 100)))])
        case (.setBrightness, .fan):
            guard let level else { return nil }
            return .device(entityID: device.id, service: "fan.set_percentage", data: ["percentage": .number(Double(level))])
        case (.openBlinds, .cover), (.turnOn, .cover):
            return .device(entityID: device.id, service: "cover.open_cover", data: [:])
        case (.closeBlinds, .cover), (.turnOff, .cover):
            return .device(entityID: device.id, service: "cover.close_cover", data: [:])
        case (.lock, .lock), (.closeBlinds, .lock):
            return .device(entityID: device.id, service: "lock.lock", data: [:])
        case (.unlock, .lock):
            return .device(entityID: device.id, service: "lock.unlock", data: [:])
        case (.setTemperature, .climate):
            guard let temperature, (5...35).contains(temperature) else { return nil }
            return .device(entityID: device.id, service: "climate.set_temperature", data: ["temperature": .number(temperature)])
        case (.turnOn, .switch), (.turnOn, .fan), (.turnOn, .mediaPlayer), (.turnOn, .climate), (.turnOn, .humidifier):
            return .device(entityID: device.id, service: "\(device.domain).turn_on", data: [:])
        case (.turnOff, .light), (.turnOff, .switch), (.turnOff, .fan), (.turnOff, .mediaPlayer), (.turnOff, .climate), (.turnOff, .humidifier):
            return .device(entityID: device.id, service: "\(device.domain).turn_off", data: [:])
        default:
            return nil
        }
    }
}

// MARK: - Finding devices from words

extension RuleDevice {
    /// The devices an action's words stand for, and whether they were found through a room or a kind
    /// ("le salon", "les lumières") rather than by name.
    static func matching(_ target: String?, for action: RuleDraft.ActionKind, in devices: [RuleDevice]) -> (devices: [RuleDevice], byPlace: Bool) {
        let words = RuleWords(target ?? "")
        var kinds: Set<DeviceKind> = switch action {
        case .setBrightness: [.light, .cover, .fan]
        case .openBlinds, .closeBlinds: [.cover]
        case .lock, .unlock: [.lock]
        case .setTemperature: [.climate]
        case .wait, .notifyMe: []
        case .turnOn, .turnOff: [.light, .switch, .fan, .mediaPlayer, .climate, .humidifier, .cover, .scene]
        }
        if let named = words.kinds, !named.isDisjoint(with: kinds) { kinds.formIntersection(named) }
        let candidates = devices.filter { kinds.contains($0.kind) }

        if words.meansEverything {
            let everything: Set<DeviceKind> = words.kinds ?? [.light, .switch, .fan, .mediaPlayer]
            return (candidates.filter { everything.contains($0.kind) }, true)
        }
        // By name: every word of the device's name is in the request ("la prise café", "les volets du salon").
        let byName = candidates.filter { !RuleWords($0.name).set.isEmpty && RuleWords($0.name).set.isSubset(of: words.set) }
        if !byName.isEmpty { return (byName, false) }
        // By room: "le salon" is the lights of the living room, or the kind named with it.
        let areas = Set(devices.compactMap(\.area).filter { words.set.isSuperset(of: RuleWords($0).set) })
        if !areas.isEmpty {
            let inRooms = candidates.filter { $0.area.map(areas.contains) ?? false }
            let preferred = words.kinds == nil ? inRooms.filter { $0.kind == .light } : inRooms
            return (preferred.isEmpty ? inRooms : preferred, true)
        }
        // By kind only: "la clim" is the climate device whose name says so, or the only one.
        if words.kinds != nil {
            let named = candidates.filter { device in
                RuleWords(device.name).set.contains { name in words.kindWords.contains { name.hasPrefix($0) } }
            }
            if named.count == 1 || candidates.count == 1 { return (named.isEmpty ? candidates : named, false) }
            return (named.isEmpty ? candidates : named, true)
        }
        // A word of the name ("le couloir" for the light "Couloir").
        let partial = candidates.filter { !RuleWords($0.name).set.isDisjoint(with: words.set) }
        return (partial, partial.count > 1)
    }

    /// The device a trigger watches: named or in the named room, else in a room the rule acts on, else the only one.
    static func watched(_ place: String?, among sensors: [RuleDevice], nearAreas: Set<String>) -> RuleDevice? {
        let words = RuleWords(place ?? "")
        if !words.set.isEmpty {
            if let named = sensors.first(where: { !RuleWords($0.name).set.isDisjoint(with: words.set) }) { return named }
            if let inRoom = sensors.first(where: { $0.area.map { words.set.isSuperset(of: RuleWords($0).set) } ?? false }) { return inRoom }
        }
        let near = sensors.filter { $0.area.map(nearAreas.contains) ?? false }
        if near.count == 1 { return near[0] }
        return sensors.count == 1 ? sensors[0] : nil
    }
}

/// The meaningful words of a request or a name, without accents, articles or prepositions.
struct RuleWords {
    let set: Set<String>

    init(_ text: String) {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        set = Set(words.filter { $0.count > 1 && !Self.stopWords.contains($0) })
    }

    func contains(phrase: String) -> Bool {
        let other = RuleWords(phrase).set
        return !other.isEmpty && other.isSubset(of: set)
    }

    var meansEverything: Bool { !set.isDisjoint(with: ["tout", "tous", "toutes", "everything", "all"]) }

    /// The kinds of device the words name ("la clim", "les lumières"), if any.
    var kinds: Set<DeviceKind>? {
        let found = Set(set.compactMap { Self.kindsByWord[$0] })
        return found.isEmpty ? nil : found
    }

    var kindWords: Set<String> {
        let words = set
        return words.filter { Self.kindsByWord[$0] != nil }
    }

    /// "Lumière chaude" in kelvins.
    var colorTemperature: Double? {
        if !set.isDisjoint(with: ["chaude", "chaud", "warm"]) { return 2700 }
        if !set.isDisjoint(with: ["froide", "froid", "cool"]) { return 5000 }
        return nil
    }

    private static let stopWords: Set<String> = [
        "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux", "mon", "ma", "mes", "notre", "nos", "dans", "et", "en",
        "the", "my", "our", "in", "of", "and", "on",
    ]

    private static let kindsByWord: [String: DeviceKind] = [
        "lumiere": .light, "lumieres": .light, "lampe": .light, "lampes": .light, "eclairage": .light, "light": .light, "lights": .light, "lamp": .light,
        "clim": .climate, "climatisation": .climate, "climatiseur": .climate, "chauffage": .climate, "thermostat": .climate,
        "radiateur": .climate, "radiateurs": .climate, "heating": .climate, "ac": .climate,
        "volet": .cover, "volets": .cover, "store": .cover, "stores": .cover, "blinds": .cover, "shutters": .cover,
        "musique": .mediaPlayer, "enceinte": .mediaPlayer, "enceintes": .mediaPlayer, "tele": .mediaPlayer, "tv": .mediaPlayer, "speaker": .mediaPlayer,
        "ventilateur": .fan, "ventilo": .fan, "fan": .fan,
        "prise": .switch, "prises": .switch, "plug": .switch,
        "porte": .lock, "serrure": .lock, "door": .lock, "lock": .lock,
        "scene": .scene,
    ]
}

extension RuleDraft {
    /// "19:00", "7:5", "19 h" or "19h30" as Home Assistant's "19:00:00"; `nil` when it isn't a time of day.
    static func clockTime(_ text: String) -> String? {
        let parts = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let hour = parts.first, (0...23).contains(hour) else { return nil }
        let minute = parts.count > 1 ? parts[1] : 0
        guard (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d:00", hour, minute)
    }

    /// A time written in a sentence: "à 19 h", "à 7h30", "at 7:15".
    static func timeInSentence(_ text: String) -> String? {
        guard let range = text.range(of: #"\b\d{1,2}\s?(h|:)\s?\d{0,2}"#, options: .regularExpression) else { return nil }
        return clockTime(String(text[range]))
    }
}
