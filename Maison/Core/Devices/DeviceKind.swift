import Foundation

/// Device type, derived from the domain of its main Home Assistant entity.
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
    case automation
    case other

    init(entityID: String) {
        let domain = entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        switch domain {
        case "switch", "input_boolean": self = .switch
        case "water_heater": self = .climate
        default: self = DeviceKind(rawValue: domain) ?? .other
        }
    }

    /// The inline control shown in lists, without opening the device sheet.
    var quickAction: QuickAction {
        switch self {
        case .light, .cover, .fan: .level
        case .switch, .valve, .automation: .toggle
        case .climate, .humidifier: .setpoint
        case .mediaPlayer: .playback
        case .scene, .script, .button, .vacuum: .run
        case .lock, .sensor, .binarySensor, .camera, .alarm, .other: .state
        }
    }
}

enum QuickAction: Sendable, Equatable {
    case level
    case toggle
    case setpoint
    case playback
    case run
    case state
}

/// The steps of the level pill in lists: each tap moves to the next 10 % in its direction.
enum LevelStep {
    /// The level after one tap, snapped to a multiple of 10 % within 0…1.
    /// From 83 %, "+" gives 90 % and "−" gives 80 %; "−" at 10 % gives 0, which turns the device off.
    static func next(from level: Double, increasing: Bool) -> Double {
        // The tolerance keeps a level already on a step, such as 0.3 stored as 0.30000000000000004, on that step.
        let tenths = level * 10
        let step = increasing ? (tenths + 1e-6).rounded(.down) + 1 : (tenths - 1e-6).rounded(.up) - 1
        return min(max(step, 0), 10) / 10
    }
}

extension DeviceKind {
    /// Section title used when grouping devices by kind.
    var title: LocalizedStringResource {
        switch self {
        case .light: "Lights"
        case .switch: "Switches"
        case .climate: "Climate"
        case .cover: "Blinds & Shutters"
        case .lock: "Locks"
        case .mediaPlayer: "Speakers & TVs"
        case .fan: "Fans"
        case .sensor: "Sensors"
        case .binarySensor: "Detectors"
        case .vacuum: "Vacuums"
        case .camera: "Cameras"
        case .alarm: "Security"
        case .humidifier: "Humidifiers"
        case .valve: "Valves"
        case .scene: "Scenes"
        case .script: "Scripts"
        case .button: "Buttons"
        case .automation: "Automations"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .light: "lightbulb.fill"
        case .switch: "powerplug.fill"
        case .climate: "thermometer.sun.fill"
        case .cover: "blinds.horizontal.closed"
        case .lock: "lock.fill"
        case .mediaPlayer: "hifispeaker.fill"
        case .fan: "fan.fill"
        case .sensor: "gauge.with.dots.needle.33percent"
        case .binarySensor: "sensor.fill"
        case .vacuum: "fan.oscillation.fill"
        case .camera: "video.fill"
        case .alarm: "shield.lefthalf.filled"
        case .humidifier: "humidifier.fill"
        case .valve: "spigot.fill"
        case .scene: "sparkles"
        case .script: "scroll.fill"
        case .button: "button.programmable"
        case .automation: "clock.fill"
        case .other: "square.dashed"
        }
    }
}
