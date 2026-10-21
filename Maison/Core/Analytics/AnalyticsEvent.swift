import Foundation

/// What Maison is allowed to record. A call site cannot attach a device name, a measurement,
/// a document, an address, or a score's value: the only properties are these tokens.
enum AnalyticsEvent: Equatable, Sendable {
    case appOpened
    /// `screen` is a fixed token (`home`, `room`), never the room's or the server's name.
    case screenViewed(AnalyticsScreen)
    /// Which score was opened. The number itself stays on the device.
    case scoreOpened(AnalyticsScore)
    /// Which connector reached a source. The address stays on the device.
    case sourceConnected(AnalyticsConnector)
    /// Which kind of document was scanned. The contents stay on the device.
    case documentScanned(AnalyticsDocument)

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .screenViewed: "screen_viewed"
        case .scoreOpened: "score_opened"
        case .sourceConnected: "source_connected"
        case .documentScanned: "document_scanned"
        }
    }

    var properties: [String: String] {
        switch self {
        case .appOpened:
            [:]
        case .screenViewed(let screen):
            ["screen": screen.rawValue]
        case .scoreOpened(let score):
            ["score": score.rawValue]
        case .sourceConnected(let connector):
            ["connector": connector.rawValue]
        case .documentScanned(let kind):
            ["kind": kind.rawValue]
        }
    }
}

enum AnalyticsScreen: String, CaseIterable, Sendable {
    case onboarding
    case home
    case rooms
    case room
    case automations
    case settings
}

enum AnalyticsScore: String, CaseIterable, Sendable {
    case comfort
    case energy
    case network
}

enum AnalyticsConnector: String, CaseIterable, Sendable {
    case homeAssistant = "home_assistant"
}

/// Kinds of document a person can scan. Add a case to record a new kind; there is no free-text field.
enum AnalyticsDocument: String, CaseIterable, Sendable {
    case barcode
    case energyLabel = "energy_label"
    case bill
    case manual
}

enum AnalyticsPayload {
    /// SDK properties that describe the app and the anonymous session.
    /// Device name, vendor id, timezone and network path are not in this set.
    static let allowedSDKProperties: Set<String> = [
        "$lib",
        "$lib_version",
        "$os_name",
        "$os_version",
        "$app_name",
        "$app_version",
        "$app_build",
        "$app_namespace",
        "$device_type",
        "$device_manufacturer",
        "$device_model",
        "$screen_width",
        "$screen_height",
        "$locale",
        "$session_id",
        "$process_person_profile",
        "$geoip_disable",
        "$is_identified",
        "$is_testflight",
        "$is_emulator",
        "$is_sideloaded",
    ]

    /// `nil` drops the event. Anything that is not one of our events, or a property outside its allowlist, is removed.
    static func filtered(name: String, properties: [String: Any]) -> [String: Any]? {
        guard let allowed = allowedProperties(forEventNamed: name) else { return nil }
        var kept: [String: Any] = [:]
        for (key, value) in properties {
            if key.hasPrefix("$") {
                guard allowedSDKProperties.contains(key) else { continue }
                kept[key] = value
                continue
            }
            guard let permitted = allowed[key], let text = value as? String, permitted.contains(text) else { continue }
            kept[key] = text
        }
        return kept
    }

    private static func allowedProperties(forEventNamed name: String) -> [String: Set<String>]? {
        switch name {
        case "app_opened":
            [:]
        case "screen_viewed":
            ["screen": Set(AnalyticsScreen.allCases.map(\.rawValue))]
        case "score_opened":
            ["score": Set(AnalyticsScore.allCases.map(\.rawValue))]
        case "source_connected":
            ["connector": Set(AnalyticsConnector.allCases.map(\.rawValue))]
        case "document_scanned":
            ["kind": Set(AnalyticsDocument.allCases.map(\.rawValue))]
        default:
            nil
        }
    }
}

/// The project token from Info.plist. Empty, unsubstituted and personal keys count as absent.
enum AnalyticsKey {
    static let infoDictionaryKey = "PostHogAPIKey"
    static let placeholder = "phc_your_project_key"

    static func usable(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        guard !trimmed.contains("$(") else { return nil }
        guard trimmed.hasPrefix("phc_"), trimmed != placeholder else { return nil }
        return trimmed
    }
}
