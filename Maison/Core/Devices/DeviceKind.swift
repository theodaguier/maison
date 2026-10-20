import Foundation

/// Type d'appareil, déduit du domaine de l'entité Home Assistant principale.
enum DeviceKind: String, CaseIterable, Sendable {
    case light
    case `switch`
    case climate
    case cover
    case lock
    case mediaPlayer = "media_player"
    case fan
    case sensor
    case binarySensor = "binary_sensor"
    case vacuum
    case camera
    case alarm = "alarm_control_panel"
    case humidifier
    case valve
    case scene
    case script
    case button
    case other

    init(entityID: String) {
        let domain = entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        switch domain {
        case "switch", "input_boolean": self = .switch
        case "water_heater": self = .climate
        default: self = DeviceKind(rawValue: domain) ?? .other
        }
    }

    /// Action rapide proposée dans les listes, sans ouvrir la fiche.
    var quickAction: QuickAction {
        switch self {
        case .light, .cover, .fan: .gauge
        case .switch, .valve: .toggle
        case .climate, .humidifier: .setpoint
        case .mediaPlayer: .playback
        case .scene, .script, .button, .vacuum: .run
        case .lock, .sensor, .binarySensor, .camera, .alarm, .other: .state
        }
    }
}

enum QuickAction: Sendable, Equatable {
    case gauge
    case toggle
    case setpoint
    case playback
    case run
    case state
}
