import Foundation

// Adding any integration from Maison, as Home Assistant's own "Add integration" does: its catalog,
// the devices it found on the network, and the steps of a flow (a form, a menu, a page to sign in on).
// Nothing here names a brand: the catalog and the steps come from the server.

/// One integration the server can add, from its catalog.
struct IntegrationDescription: Sendable, Hashable, Identifiable {
    let domain: String
    let name: String
    /// `local_polling`, `cloud_push`…: whether it needs an account online.
    let iotClass: String?
    var id: String { domain }

    /// Needs an account on the brand's site.
    var isCloud: Bool { iotClass?.hasPrefix("cloud") == true }

    /// `integration/descriptions`: integrations, brands that group several of them, and helpers are left
    /// out. Only those that can be added from the settings (a config flow) are kept.
    static func parse(_ result: JSONValue) -> [IntegrationDescription] {
        var found: [String: IntegrationDescription] = [:]
        func read(_ entries: [String: JSONValue]?) {
            for (domain, entry) in entries ?? [:] {
                if let nested = entry["integrations"]?.objectValue {
                    read(nested)
                    continue
                }
                guard entry["config_flow"]?.boolValue == true, entry["integration_type"]?.stringValue != "virtual",
                      let name = entry["name"]?.stringValue, !name.isEmpty else { continue }
                found[domain] = IntegrationDescription(domain: domain, name: name, iotClass: entry["iot_class"]?.stringValue)
            }
        }
        read(result["core"]?["integration"]?.objectValue)
        read(result["custom"]?["integration"]?.objectValue)
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Names that contain `query`, accents and case ignored; the ones that start with it first.
    static func search(_ query: String, in catalog: [IntegrationDescription]) -> [IntegrationDescription] {
        let needle = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return [] }
        let matches = catalog.filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle) || $0.domain.contains(needle)
        }
        return matches.sorted { lhs, rhs in
            let left = lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(needle)
            let right = rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(needle)
            return left != right ? left : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// A device Home Assistant found on the network and waits to add.
struct DiscoveredDevice: Sendable, Hashable, Identifiable {
    let flowID: String
    let domain: String
    /// The device's own name when it gives one ("Salon"), otherwise `nil`.
    let name: String?
    var id: String { flowID }
}

/// Where a flow is: what to show, or how it ended.
enum FlowStep: Equatable, Sendable {
    case form(Form)
    case menu(flowID: String, stepID: String, options: [String])
    /// A page to open, usually to sign in on the brand's site.
    case external(flowID: String, stepID: String, url: URL)
    /// The server is working on it (pairing, a download).
    case progress(flowID: String, stepID: String)
    case created(title: String)
    case aborted(reason: String)

    struct Form: Equatable, Sendable {
        let flowID: String
        let stepID: String
        let fields: [FlowField]
        /// Error keys by field, `base` for the whole form.
        let errors: [String: String]
        let placeholders: [String: String]
        var lastStep: Bool?

        /// A required field Maison can't show yet: the step can't be done here.
        var hasUnsupportedRequirement: Bool {
            fields.contains { field in
                if case .unsupported = field.kind { return field.isRequired && field.defaultValue == nil }
                return false
            }
        }
    }

    var flowID: String? {
        switch self {
        case .form(let form): form.flowID
        case .menu(let id, _, _), .external(let id, _, _), .progress(let id, _): id
        case .created, .aborted: nil
        }
    }

    /// A step as `POST /api/config/config_entries/flow` returns it.
    static func parse(_ raw: JSONValue) -> FlowStep {
        let flowID = raw["flow_id"]?.stringValue ?? ""
        let stepID = raw["step_id"]?.stringValue ?? ""
        switch raw["type"]?.stringValue {
        case "form":
            let errors = (raw["errors"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
            let placeholders = (raw["description_placeholders"]?.objectValue ?? [:]).compactMapValues { $0.stringValue ?? $0.doubleValue.map { "\($0)" } }
            return .form(Form(flowID: flowID, stepID: stepID, fields: (raw["data_schema"]?.arrayValue ?? []).map(FlowField.parse),
                              errors: errors, placeholders: placeholders, lastStep: raw["last_step"]?.boolValue))
        case "menu":
            let options = raw["menu_options"].map { $0.arrayValue?.compactMap(\.stringValue) ?? Array(($0.objectValue ?? [:]).keys).sorted() } ?? []
            return .menu(flowID: flowID, stepID: stepID, options: options)
        case "external":
            guard let url = raw["url"]?.stringValue.flatMap(URL.init(string:)) else { return .aborted(reason: "unknown") }
            return .external(flowID: flowID, stepID: stepID, url: url)
        case "external_done", "progress", "show_progress", "progress_done":
            return .progress(flowID: flowID, stepID: stepID)
        case "create_entry":
            return .created(title: raw["title"]?.stringValue ?? "")
        case "abort":
            return .aborted(reason: raw["reason"]?.stringValue ?? "unknown")
        default:
            return .aborted(reason: "unknown")
        }
    }
}

/// One field of a flow's form, as `voluptuous_serialize` or a selector describes it.
struct FlowField: Equatable, Sendable, Identifiable {
    let name: String
    let kind: Kind
    let isRequired: Bool
    let defaultValue: JSONValue?
    var id: String { name }

    enum Kind: Equatable, Sendable {
        case text(isSecret: Bool)
        case number(isInteger: Bool)
        case toggle
        /// Values and their labels, in order.
        case choice([Choice])
        /// Fixed: sent as it is.
        case constant(JSONValue)
        case unsupported(String)
    }

    struct Choice: Equatable, Sendable, Hashable {
        let value: String
        let label: String
    }

    static func parse(_ raw: JSONValue) -> FlowField {
        let name = raw["name"]?.stringValue ?? ""
        let required = raw["required"]?.boolValue ?? false
        let fallback = raw["default"] ?? raw["description"]?["suggested_value"]
        return FlowField(name: name, kind: kind(raw, name: name), isRequired: required, defaultValue: fallback)
    }

    private static func kind(_ raw: JSONValue, name: String) -> Kind {
        if let selector = raw["selector"]?.objectValue, let (type, config) = selector.first {
            switch type {
            case "text":
                let secret = config["type"]?.stringValue == "password"
                return config["multiple"]?.boolValue == true ? .unsupported(type) : .text(isSecret: secret)
            case "number":
                let step = config["step"]?.doubleValue ?? 1
                return .number(isInteger: step == step.rounded())
            case "boolean":
                return .toggle
            case "select":
                guard config["multiple"]?.boolValue != true else { return .unsupported(type) }
                return .choice(choices(config["options"]))
            default:
                return .unsupported(type)
            }
        }
        switch raw["type"]?.stringValue {
        case "string": return .text(isSecret: name.contains("password") || name.contains("token") || name.contains("secret"))
        case "integer": return .number(isInteger: true)
        case "float": return .number(isInteger: false)
        case "boolean": return .toggle
        case "select": return .choice(choices(raw["options"]))
        case "constant": return .constant(raw["value"] ?? .null)
        case let type: return .unsupported(type ?? "")
        }
    }

    /// `[["a", "A"]]`, `{"a": "A"}`, `["a"]` or `[{"value": "a", "label": "A"}]`.
    private static func choices(_ raw: JSONValue?) -> [Choice] {
        if let object = raw?.objectValue {
            return object.map { Choice(value: $0.key, label: $0.value.stringValue ?? $0.key) }.sorted { $0.label < $1.label }
        }
        return (raw?.arrayValue ?? []).compactMap { item in
            if let pair = item.arrayValue, let value = pair.first?.stringValue ?? pair.first?.doubleValue.map({ "\($0)" }) {
                return Choice(value: value, label: pair.dropFirst().first?.stringValue ?? value)
            }
            if let value = item["value"]?.stringValue { return Choice(value: value, label: item["label"]?.stringValue ?? value) }
            return item.stringValue.map { Choice(value: $0, label: $0) }
        }
    }
}

/// Runs a flow's steps; the server's REST API, or the sample home.
protocol FlowDriver: Sendable {
    func start(_ domain: String) async throws -> FlowStep
    func current(_ flowID: String) async throws -> FlowStep
    func submit(_ flowID: String, answers: [String: JSONValue]) async throws -> FlowStep
    func cancel(_ flowID: String) async
}

extension ConfigFlowClient: FlowDriver {
    func start(_ domain: String) async throws -> FlowStep {
        try await FlowStep.parse(request("POST", "api/config/config_entries/flow", body: ["handler": .string(domain), "show_advanced_options": false]))
    }

    func current(_ flowID: String) async throws -> FlowStep {
        try await FlowStep.parse(request("GET", "api/config/config_entries/flow/\(flowID)"))
    }

    func submit(_ flowID: String, answers: [String: JSONValue]) async throws -> FlowStep {
        try await FlowStep.parse(request("POST", "api/config/config_entries/flow/\(flowID)", body: .object(answers)))
    }

    func cancel(_ flowID: String) async {
        _ = try? await request("DELETE", "api/config/config_entries/flow/\(flowID)")
    }
}

/// The sample home: a device found on the network asks for nothing, a search result for its address.
struct DemoFlowDriver: FlowDriver {
    func start(_ domain: String) async throws -> FlowStep {
        .form(.init(flowID: "demo-\(domain)", stepID: "user",
                    fields: [FlowField(name: "host", kind: .text(isSecret: false), isRequired: true, defaultValue: nil)],
                    errors: [:], placeholders: [:]))
    }

    func current(_ flowID: String) async throws -> FlowStep {
        // A box waits for its button; other found devices only for a confirmation.
        .form(.init(flowID: flowID, stepID: flowID.contains("freebox") ? "link" : "confirm", fields: [], errors: [:], placeholders: [:]))
    }

    func submit(_ flowID: String, answers: [String: JSONValue]) async throws -> FlowStep {
        .created(title: String(flowID.dropFirst("demo-".count)))
    }

    func cancel(_ flowID: String) async {}
}

extension HomeAssistantConnection {
    /// The integrations the server can add.
    func integrationCatalog() async throws -> [IntegrationDescription] {
        try await IntegrationDescription.parse(send(["type": "integration/descriptions"]))
    }

    /// Devices found on the network, with the name they gave when they have one.
    func discoveredDevices() async throws -> [DiscoveredDevice] {
        let sources: Set = ["zeroconf", "ssdp", "dhcp", "bluetooth", "homekit", "usb", "mqtt", "discovery", "integration_discovery"]
        return try await (send(["type": "config_entries/flow/progress"]).arrayValue ?? []).compactMap { flow in
            guard let id = flow["flow_id"]?.stringValue, let handler = flow["handler"]?.stringValue,
                  sources.contains(flow["context"]?["source"]?.stringValue ?? "") else { return nil }
            return DiscoveredDevice(flowID: id, domain: handler, name: flow["context"]?["title_placeholders"]?["name"]?.stringValue)
        }
    }

    /// Labels of an integration's flow in `language`, keyed like `component.<domain>.config.step.user.data.host`.
    func flowTranslations(domain: String, language: String) async throws -> [String: String] {
        let result = try await send(["type": "frontend/get_translations", "language": .string(language), "category": "config",
                                     "integration": [.string(domain)]])
        return (result["resources"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
    }
}

/// The words of a flow. Home Assistant's are written for its own screens ("Submit", "Home Assistant",
/// markdown images, error codes): Maison says the common cases itself, and keeps of the server's words
/// only a short sentence, cleaned, when it tells something about the device.
struct FlowWording: Sendable {
    let domain: String
    let resources: [String: String]

    private func text(_ key: String) -> String? {
        resources["component.\(domain).config.\(key)"].flatMap { $0.isEmpty ? nil : $0 }
    }

    func title(step: String) -> String? { text("step.\(step).title").flatMap { Self.plain($0, limit: 40) } }

    func label(field: String, step: String) -> String {
        text("step.\(step).data.\(field)").flatMap { Self.plain($0, limit: 40) } ?? field.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func help(field: String, step: String) -> String? {
        text("step.\(step).data_description.\(field)").flatMap { Self.plain($0, limit: 120) }
    }

    func menuOption(_ option: String, step: String) -> String {
        text("step.\(step).menu_options.\(option)").flatMap { Self.plain($0, limit: 60) } ?? option.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// What to do on this step, in one or two short sentences.
    func hint(for form: FlowStep.Form) -> String? {
        let server = text("step.\(form.stepID).description").flatMap { Self.plain(Self.fill($0, form.placeholders)) }
        guard form.fields.isEmpty, !form.stepID.contains("confirm") else { return server }
        // A step with nothing to fill waits for the device: its button, or a prompt on its screen.
        return server ?? String(localized: "Press the button on the device, or accept on its screen, then tap Add.")
    }

    func error(_ key: String) -> String {
        switch key {
        case "cannot_connect", "invalid_host", "timeout_connect", "timeout":
            String(localized: "The device doesn’t answer. Check that it’s on and on the same network, then try again.")
        case "invalid_auth", "auth_failed", "invalid_credentials":
            String(localized: "The username or password was refused.")
        case "register_failed", "linking", "not_authorized", "unauthorized", "pairing_failed":
            String(localized: "The device didn’t authorise your server. Press its button, then tap Add again.")
        default:
            text("error.\(key)").flatMap { Self.plain($0) } ?? String(localized: "That didn’t work. Try again.")
        }
    }

    func abort(_ reason: String) -> String {
        switch reason {
        case "already_configured", "already_in_progress", "single_instance_allowed", "reauth_successful":
            String(localized: "It’s already added.")
        case "no_devices_found", "not_found":
            String(localized: "No device was found on the network. Check that it’s on, then try again.")
        case "cannot_connect", "timeout_connect":
            String(localized: "The device doesn’t answer. Check that it’s on and on the same network, then try again.")
        case "missing_credentials", "missing_configuration", "oauth_error", "oauth_unauthorized", "authorize_url_timeout":
            String(localized: "It needs an account link your server doesn’t have yet, so it can’t be added from Maison for now.")
        case "not_supported", "not_supported_device", "unsupported_device":
            String(localized: "This device isn’t supported.")
        default:
            text("abort.\(reason)").flatMap { Self.plain($0) } ?? String(localized: "Your server couldn’t add it.")
        }
    }

    /// "{name}" replaced by its value.
    static func fill(_ text: String, _ placeholders: [String: String]) -> String {
        placeholders.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    /// Markdown images dropped, links and emphasis kept as their text, "Home Assistant" as the server and
    /// its "Submit" as Maison's "Add"; the first sentence, or `nil` when it's longer than `limit`.
    static func plain(_ text: String, limit: Int = 160) -> String? {
        var text = text
        let rewrites: [(String, String)] = [
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),
            (#"(?i)\*\*\s*(submit|soumettre|valider|envoyer)\s*\*\*"#, String(localized: "“Add”")),
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"[*_`]{1,2}([^*_`]+)[*_`]{1,2}"#, "$1"),
            (#"Home Assistant"#, String(localized: "your server")),
            (#"(?i)["“«]\s*(submit|soumettre|valider|envoyer)\s*["”»]"#, String(localized: "“Add”")),
            (#"\s+"#, " "),
        ]
        for (pattern, template) in rewrites {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if let end = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression) { text = String(text[..<end.upperBound]).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty || text.count > limit ? nil : text
    }
}
