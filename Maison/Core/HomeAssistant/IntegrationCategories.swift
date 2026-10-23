import Foundation

// Which part of the home an integration serves, from Home Assistant's own documentation categories, and
// how many homes use it, from its public analytics. Both are built by `ci/integration-categories.py`:
// Maison never picks a brand by hand.

/// The groups Maison shows integrations in: the three scores, safety, presence, the hubs that bring
/// devices of every kind, and the rest.
enum IntegrationGroup: String, CaseIterable, Sendable {
    case energy, comfort, network, safety, presence, hubs, other

    /// Home Assistant category prefixes, as in `energy.meters_monitoring`.
    static let prefixes: [IntegrationGroup: [String]] = [
        .energy: ["energy", "plugs_switches", "climate.water_heaters", "water.meters_leak_detection"],
        .comfort: ["climate", "sensors.temperature_humidity", "sensors.air_quality", "sensors", "weather_alerts.forecasts",
                   "weather_alerts.air_quality_pollen", "blinds_curtains"],
        .network: ["computers_network.routers_network", "computers_network.monitoring"],
        .safety: ["security_safety", "water.meters_leak_detection", "sensors.motion_presence", "weather_alerts.public_warnings"],
        .presence: ["presence_location"],
        .hubs: ["hubs_protocols"],
    ]

    /// The groups `categories` belong to; `other` when none.
    static func of(_ categories: [String]) -> [IntegrationGroup] {
        let found = allCases.filter { group in
            (prefixes[group] ?? []).contains { prefix in categories.contains { IntegrationCategories.matches($0, prefix) } }
        }
        return found.isEmpty ? [.other] : found
    }
}

/// An integration's categories and how many homes use it.
struct IntegrationProfile: Decodable, Sendable {
    let categories: [String]
    /// The kinds of entities it creates: `sensor`, `device_tracker`, `weather`…
    let platforms: [String]
    let installs: Int

    private enum CodingKeys: String, CodingKey {
        case categories = "c"
        case platforms = "p"
        case installs = "n"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([String].self, forKey: .categories)
        platforms = try container.decodeIfPresent([String].self, forKey: .platforms) ?? []
        installs = try container.decode(Int.self, forKey: .installs)
    }
}

/// What a source needs from an integration: to serve its part of the home, and to create the kind of
/// entity it reads. A box with an alarm is in the alarms' category, but it has no smoke sensor.
struct IntegrationNeed: Sendable, Equatable {
    /// Home Assistant category prefixes.
    let categories: [String]
    /// Any of these platforms.
    let platforms: [String]
}

enum IntegrationCategories {
    static let all: [String: IntegrationProfile] = {
        guard let url = Bundle.main.url(forResource: "IntegrationCategories", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: IntegrationProfile].self, from: data)) ?? [:]
    }()

    /// `energy.meters_monitoring` matches `energy` and itself.
    static func matches(_ category: String, _ prefix: String) -> Bool {
        category == prefix || category.hasPrefix(prefix + ".")
    }
}

extension IntegrationDescription {
    var categories: [String] { IntegrationCategories.all[domain]?.categories ?? [] }
    var installs: Int { IntegrationCategories.all[domain]?.installs ?? 0 }
    var platforms: [String] { IntegrationCategories.all[domain]?.platforms ?? [] }
    var groups: [IntegrationGroup] { IntegrationGroup.of(categories) }

    /// Serves one of `prefixes` (Home Assistant categories).
    func serves(_ prefixes: [String]) -> Bool {
        prefixes.contains { prefix in categories.contains { IntegrationCategories.matches($0, prefix) } }
    }

    /// The integrations serving `prefixes`, the most used first.
    static func serving(_ prefixes: [String], in catalog: [IntegrationDescription]) -> [IntegrationDescription] {
        catalog.filter { $0.serves(prefixes) }.sorted { $0.installs > $1.installs }
    }

    /// The integrations that serve the need and create the entity it reads, the most used first.
    static func serving(_ need: IntegrationNeed, in catalog: [IntegrationDescription]) -> [IntegrationDescription] {
        serving(need.categories, in: catalog).filter { item in need.platforms.contains { item.platforms.contains($0) } }
    }
}

extension FlowStep.Form {
    /// Every field has its answer already (a default, a constant) or can stay empty: the step asks
    /// nothing, so Maison answers it alone.
    var asksNothing: Bool {
        // A step with no field at all is a confirmation only when it says so: "link" or "pair" waits for a
        // button pressed on the device (a box, a bridge), which only the person can do.
        if fields.isEmpty { return errors.isEmpty && stepID.contains("confirm") }
        return errors.isEmpty && fields.allSatisfy { field in
            switch field.kind {
            case .constant: true
            case .unsupported: !field.isRequired || field.defaultValue != nil
            default: !field.isRequired || (field.defaultValue.map { $0 != .string("") && $0 != .null } ?? false)
            }
        }
    }

    /// The answers a step that asks nothing is submitted with.
    var defaultAnswers: [String: JSONValue] {
        var answers: [String: JSONValue] = [:]
        for field in fields {
            if case .constant(let value) = field.kind { answers[field.name] = value } else if let value = field.defaultValue { answers[field.name] = value }
        }
        return answers
    }
}

extension FlowDriver {
    /// Answers the steps that ask nothing, up to a few. Stops on one that needs the person.
    func answerWhatAsksNothing(_ step: FlowStep) async throws -> FlowStep {
        var step = step
        for _ in 0..<4 {
            guard case .form(let form) = step, form.asksNothing else { return step }
            step = try await submit(form.flowID, answers: form.defaultAnswers)
        }
        return step
    }

    /// Adds the first of `candidates` whose steps ask nothing; the others are dropped unchanged.
    /// Returns the one added.
    func addFirstAskingNothing(_ candidates: [IntegrationDescription]) async -> IntegrationDescription? {
        for candidate in candidates {
            guard let started = try? await start(candidate.domain),
                  let step = try? await answerWhatAsksNothing(started) else { continue }
            if case .created = step { return candidate }
            if let flowID = step.flowID { await cancel(flowID) }
        }
        return nil
    }
}
