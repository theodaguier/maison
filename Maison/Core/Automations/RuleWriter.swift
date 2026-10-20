import Foundation
import FoundationModels

/// Whether this iPhone can use Apple's on-device model: Apple Intelligence on, model downloaded, language supported.
enum Intelligence {
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.isAvailable && model.supportsLocale(.current)
    }

    /// The user's language in English ("French"), for the model's instructions.
    static var languageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
    }
}

/// Turns a request ("le soir à 19 h, ferme les volets") into a rule to review, with the on-device model.
enum RuleWriter {
    static func propose(_ request: String, devices: [RuleDevice], notifyService: String?) async throws -> RuleProposal {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: prompt(request, devices: devices),
            generating: RuleDraft.self,
            options: GenerationOptions(temperature: 0)
        )
        return response.content.proposal(for: request, devices: devices, notifyService: notifyService)
    }

    private static var instructions: String {
        """
        You turn a request into a home automation rule: one trigger, optional conditions, then actions.
        Use only devices from the list, by their exact id. Never invent a device.
        The trigger is the event the request starts with: a time, the sun, people leaving or arriving, \
        a device changing (motion, a door or window opening), or a measurement crossing a value.
        Add a condition only when the request states one. "At night" is onlyBetweenTimes 23:00 to 06:00.
        A room means every light listed in that room. "Close" is closeCover, "open" is openCover.
        Leave out what no kind can express and copy those words into unsupported.
        Name the rule in \(Intelligence.languageName).

        Examples:
        "Turn everything off when we all leave" → whenEveryoneHasLeft; turnOff each light, fan and speaker.
        "At night, turn the hallway light on at 20 % when there's motion" → whenDeviceChanges on the hallway \
        motion sensor to on; onlyBetweenTimes 23:00–06:00; turnOn the hallway light with percent 20.
        "Close the blinds when it's above 25°" → whenValueRisesAbove on the temperature sensor, value 25; closeCover.
        """
    }

    static func prompt(_ request: String, devices: [RuleDevice]) -> String {
        let lines = devices.map { device in
            "- \(device.id): \(device.name) (\(device.kind.rawValue)\(device.area.map { ", \($0)" } ?? ""))"
        }
        return "Devices:\n" + lines.joined(separator: "\n") + "\n\nRequest: " + request
    }
}

extension HomeStore {
    /// The devices a generated rule may use: what can be controlled or watched, and scenes.
    var ruleDevices: [RuleDevice] {
        let kinds: Set<DeviceKind> = [.light, .switch, .fan, .cover, .lock, .climate, .mediaPlayer, .humidifier, .binarySensor]
        let usable = devices.filter { kinds.contains($0.kind) || ($0.kind == .sensor && $0.numericState != nil) }
        return (usable + scenes).prefix(150).map { entity in
            RuleDevice(id: entity.entityID, name: entity.name, kind: entity.kind, area: area(of: entity)?.name)
        }
    }
}
