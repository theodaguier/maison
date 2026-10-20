/// The Home Assistant service call behind a device's primary action (tap on its row).
struct DeviceCommand: Sendable, Equatable {
    let domain: String
    let service: String

    init(domain: String, service: String) {
        self.domain = domain
        self.service = service
    }

    /// Returns the command for the entity's primary action, or `nil` when it has none
    /// (read-only sensors, or devices that need their own sheet such as climate).
    init?(primaryActionFor entity: EntityState) {
        switch entity.kind {
        case .light, .switch, .fan, .humidifier, .cover, .valve:
            self.init(domain: entity.domain, service: "toggle")
        case .lock:
            self.init(domain: "lock", service: entity.state == "locked" ? "unlock" : "lock")
        case .mediaPlayer:
            self.init(domain: "media_player", service: "media_play_pause")
        case .scene, .script:
            self.init(domain: entity.domain, service: "turn_on")
        case .button:
            self.init(domain: "button", service: "press")
        case .vacuum:
            self.init(domain: "vacuum", service: entity.state == "cleaning" ? "return_to_base" : "start")
        case .climate, .sensor, .binarySensor, .camera, .alarm, .other:
            return nil
        }
    }
}

extension EntityState {
    /// Whether the device is in its active state (on, open, unlocked, playing…).
    var isActive: Bool {
        ["on", "open", "opening", "unlocked", "playing", "cleaning", "heat", "cool", "heat_cool", "auto"].contains(state)
    }
}
