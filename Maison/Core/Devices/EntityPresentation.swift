import Foundation
import SwiftUI

/// How an entity looks in lists: its symbol, accent colour, short status and inline control.
extension EntityState {
    var deviceClass: String? { attributes["device_class"]?.stringValue }
    var unit: String? { attributes["unit_of_measurement"]?.stringValue }
    var numericState: Double? { Double(state) }

    // MARK: Values

    /// Light brightness or cover position, 0…1, when the device exposes one.
    var level: Double? {
        switch kind {
        case .light:
            guard state == "on" else { return 0 }
            return attributes["brightness"]?.doubleValue.map { $0 / 255 } ?? 1
        case .cover:
            return attributes["current_position"]?.doubleValue.map { $0 / 100 }
        case .fan:
            guard state == "on" else { return 0 }
            return attributes["percentage"]?.doubleValue.map { $0 / 100 }
        default:
            return nil
        }
    }

    var supportsLevel: Bool {
        switch kind {
        case .light:
            let modes = attributes["supported_color_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return attributes["brightness"] != nil || modes.contains { $0 != "onoff" }
        case .cover:
            return attributes["current_position"] != nil
        case .fan:
            return attributes["percentage"] != nil
        default:
            return false
        }
    }

    var targetTemperature: Double? { attributes["temperature"]?.doubleValue }
    var currentTemperature: Double? { attributes["current_temperature"]?.doubleValue }
    var temperatureStep: Double { attributes["target_temp_step"]?.doubleValue ?? 0.5 }
    var hvacAction: String? { attributes["hvac_action"]?.stringValue }

    // MARK: Appearance

    var symbolName: String {
        let name = name.lowercased()
        switch kind {
        case .light:
            if name.contains("lampadaire") || name.contains("floor") { return "lamp.floor.fill" }
            if name.contains("plafon") || name.contains("ceiling") || name.contains("suspension") { return "lamp.ceiling.fill" }
            if name.contains("led") || name.contains("strip") || name.contains("bandeau") || name.contains("ruban") { return "light.strip.2.fill" }
            if name.contains("bureau") || name.contains("desk") { return "lamp.desk.fill" }
            if name.contains("chevet") || name.contains("table") { return "lamp.table.fill" }
            return "lightbulb.fill"
        case .switch:
            return "powerplug.fill"
        case .climate:
            switch hvacAction ?? state {
            case "cooling", "cool": return "snowflake"
            case "heating", "heat": return "heater.vertical.fill"
            case "drying", "dry": return "drop.fill"
            case "fan", "fan_only": return "fan.fill"
            default: return "thermometer.medium"
            }
        case .cover:
            return state == "closed" ? "blinds.horizontal.closed" : "blinds.horizontal.open"
        case .lock:
            return state == "locked" ? "lock.fill" : "lock.open.fill"
        case .mediaPlayer:
            if deviceClass == "tv" || name.contains("tv") || name.contains("télé") { return "tv.fill" }
            return "hifispeaker.fill"
        case .sensor:
            switch deviceClass {
            case "temperature": return "thermometer.medium"
            case "humidity": return "humidity.fill"
            case "power", "energy": return "bolt.fill"
            case "battery": return "battery.75percent"
            case "illuminance": return "sun.max.fill"
            default: return "gauge.with.dots.needle.33percent"
            }
        case .binarySensor:
            switch deviceClass {
            case "door", "garage_door": return isActive ? "door.left.hand.open" : "door.left.hand.closed"
            case "window": return isActive ? "window.vertical.open" : "window.vertical.closed"
            case "motion", "occupancy", "presence": return "figure.walk.motion"
            case "moisture": return "drop.triangle.fill"
            case "smoke": return "smoke.fill"
            default: return "sensor.fill"
            }
        default:
            return kind.systemImage
        }
    }

    /// Accent used for the icon and status when the device is active; inactive devices are grey.
    var accent: Color {
        switch kind {
        case .light: .yellow
        case .switch, .valve: .green
        case .climate:
            switch hvacAction ?? state {
            case "cooling", "cool": .teal
            case "heating", "heat": .orange
            default: .blue
            }
        case .cover: .orange
        case .lock: state == "locked" ? .green : .orange
        case .mediaPlayer: .indigo
        case .fan: .teal
        case .binarySensor: .orange
        case .sensor: .blue
        case .scene, .script, .button: .indigo
        default: .accentColor
        }
    }

    var showsAccent: Bool {
        switch kind {
        case .lock, .sensor: true
        case .binarySensor: isActive
        default: isActive && !isUnavailable
        }
    }

    // MARK: Text

    /// The short status shown under the name, without the room.
    var statusText: String {
        // "Allumé · 40 %" agrees with the device's name, like the state label.
        rawStatusText.components(separatedBy: ", ").map { Phrasing.agree($0, with: name) }.joined(separator: ", ")
    }

    private var rawStatusText: String {
        if isUnavailable { return String(localized: "No Response") }
        switch kind {
        case .light, .fan:
            guard state == "on" else { return String(localized: "Off") }
            if let level, supportsLevel { return String(localized: "On, \(level.formatted(.percent.precision(.fractionLength(0))))") }
            return String(localized: "On")
        case .switch, .valve:
            return state == "on" || state == "open" ? String(localized: "On") : String(localized: "Off")
        case .cover:
            if state == "closed" { return String(localized: "Closed") }
            if let level { return String(localized: "Open at \(level.formatted(.percent.precision(.fractionLength(0))))") }
            return String(localized: "Open")
        case .climate:
            let measured = currentTemperature.map { String(localized: "\(Self.degrees($0)) measured") }
            let action: String? = switch hvacAction ?? state {
            case "cooling", "cool": String(localized: "Cooling")
            case "heating", "heat": String(localized: "Heating")
            case "drying", "dry": String(localized: "Drying")
            case "fan", "fan_only": String(localized: "Fan")
            case "off": String(localized: "Off")
            case "idle": String(localized: "Idle")
            default: nil
            }
            return [action, measured].compactMap(\.self).joined(separator: ", ")
        case .mediaPlayer:
            let title = attributes["media_title"]?.stringValue
            let artist = attributes["media_artist"]?.stringValue
            if state == "playing" || state == "paused", let title {
                return [title, artist].compactMap(\.self).joined(separator: ", ")
            }
            return state == "off" ? String(localized: "Off") : mediaStateText
        case .lock:
            let since = lastChanged.map { String(localized: "since \(Phrasing.time($0))") }
            return since ?? lockStateText
        case .sensor:
            return valueText
        case .binarySensor:
            return binaryStateText
        case .automation:
            return state == "on" ? String(localized: "On") : String(localized: "Off")
        default:
            return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The coloured state label used by read-only rows (locks, sensors…).
    var stateLabel: String {
        Phrasing.agree(rawStateLabel, with: name)
    }

    private var rawStateLabel: String {
        if domain == "person" || domain == "device_tracker" {
            switch state {
            case "home": return String(localized: "At Home")
            case "not_home": return String(localized: "Away")
            default: return state
            }
        }
        return switch kind {
        case .lock: lockStateText
        case .binarySensor: binaryStateText
        case .sensor: valueText
        case .mediaPlayer: state == "off" ? String(localized: "Off") : mediaStateText
        case .cover: state == "closed" ? String(localized: "Closed") : String(localized: "Open")
        default: isActive ? String(localized: "On") : String(localized: "Off")
        }
    }

    var valueText: String {
        guard let value = numericState else { return state }
        let formatted = value.formatted(.number.precision(.fractionLength(0...1)))
        guard let unit else { return formatted }
        return unit == "°C" || unit == "°F" ? "\(formatted)°" : "\(formatted) \(unit)"
    }

    private var lockStateText: String {
        switch state {
        case "locked": String(localized: "Locked")
        case "unlocked": String(localized: "Unlocked")
        case "jammed": String(localized: "Jammed")
        case "locking": String(localized: "Locking…")
        case "unlocking": String(localized: "Unlocking…")
        default: state.capitalized
        }
    }

    private var binaryStateText: String {
        switch deviceClass {
        case "door", "garage_door", "window", "opening": isActive ? String(localized: "Open") : String(localized: "Closed")
        case "motion", "occupancy", "presence": isActive ? String(localized: "Detected") : String(localized: "Clear")
        default: isActive ? String(localized: "On") : String(localized: "Off")
        }
    }

    private var mediaStateText: String {
        switch state {
        case "playing": String(localized: "Playing")
        case "paused": String(localized: "Paused")
        case "idle", "standby": String(localized: "Idle")
        default: String(localized: "On")
        }
    }

    static func degrees(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))°"
    }
}
