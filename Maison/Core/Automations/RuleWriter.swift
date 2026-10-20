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

/// Turns a request ("le soir à 19 h, ferme les volets") into a rule to review: the on-device model reads
/// the request, then `RuleDraft.proposal` finds the devices and checks every value.
enum RuleWriter {
    static func propose(_ request: String, devices: [RuleDevice], notifyService: String?) async throws -> RuleProposal {
        #if DEBUG
        // `-suggestedRule simple` or `complex` replays what the model answered on a Mac, through the real device
        // matching: the simulator's model can't generate (its content safety assets are missing).
        if let sample = UserDefaults.standard.string(forKey: "suggestedRule").flatMap(RuleDraft.sample) {
            try await Task.sleep(for: .seconds(2))
            return sample.proposal(for: request, devices: devices, notifyService: notifyService)
        }
        #endif
        let session = LanguageModelSession(instructions: RuleDraft.instructions)
        let response = try await session.respond(
            to: "Request: " + request,
            generating: RuleDraft.self,
            options: GenerationOptions(temperature: 0)
        )
        return response.content.proposal(for: request, devices: devices, notifyService: notifyService)
    }
}

extension HomeStore {
    /// The devices a generated rule may use: what can be controlled or watched, and scenes.
    /// They stay on the iPhone's side: the model only sees the request.
    var ruleDevices: [RuleDevice] {
        let kinds: Set<DeviceKind> = [.light, .switch, .fan, .cover, .lock, .climate, .mediaPlayer, .humidifier, .binarySensor]
        let usable = devices.filter { kinds.contains($0.kind) || ($0.kind == .sensor && $0.numericState != nil) }
        return (usable + scenes).map { entity in
            RuleDevice(id: entity.entityID, name: entity.name, kind: entity.kind, deviceClass: entity.deviceClass, area: area(of: entity)?.name)
        }
    }
}

#if DEBUG
extension RuleDraft {
    /// Answers the model gave on a Mac to the first example request and to a request that asks too much.
    static func sample(_ name: String) -> RuleDraft? {
        switch name {
        case "simple":
            RuleDraft(whenWords: "le soir à 19 h", trigger: Trigger(kind: .sunset, place: nil, time: nil, value: 1),
                      onlyAtNight: false, onlyAfterSunset: true, onlyIfSomeoneIsHome: true, onlyIfNobodyIsHome: false,
                      onlyOnWeekdays: false, onlyOnWeekend: false,
                      actions: [Action(kind: .turnOn, target: "le salon", percent: 75, temperature: nil, minutes: nil, message: nil),
                                Action(kind: .closeBlinds, target: "les volets", percent: nil, temperature: nil, minutes: nil, message: nil)],
                      unsupported: [], name: "Allumer salon et fermer volets")
        case "complex":
            RuleDraft(whenWords: "Quand l’électricité passe en heures creuses", trigger: Trigger(kind: .deviceTurnsOff, place: nil, time: nil, value: 20),
                      onlyAtNight: false, onlyAfterSunset: false, onlyIfSomeoneIsHome: false, onlyIfNobodyIsHome: false,
                      onlyOnWeekdays: false, onlyOnWeekend: false,
                      actions: [Action(kind: .turnOn, target: "le lave-linge", percent: nil, temperature: nil, minutes: nil, message: nil),
                                Action(kind: .notifyMe, target: nil, percent: nil, temperature: nil, minutes: nil, message: "il n’a pas fini au bout de 2 h")],
                      unsupported: ["Ferme", "ouvre", "coupe"], name: "Lave-linge en heures creuses")
        default:
            nil
        }
    }
}
#endif
