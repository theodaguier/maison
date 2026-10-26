import Foundation

/// Device type, derived from the domain of its main Home Assistant entity.
public enum DeviceKind: String, CaseIterable, Sendable {
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

    public init(entityID: String) {
        let domain = entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        switch domain {
        case "switch", "input_boolean": self = .switch
        case "water_heater": self = .climate
        default: self = DeviceKind(rawValue: domain) ?? .other
        }
    }
}
