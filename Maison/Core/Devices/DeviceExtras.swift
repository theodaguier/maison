import Foundation

// MARK: - Related entities

extension HomeStore {
    /// The other entities of the same physical device (a plug's power sensor, a lock's battery),
    /// hidden ones included.
    func siblings(of entity: EntityState) -> [EntityState] {
        guard let device = layout.deviceByEntity[entity.entityID] else { return [] }
        return states.values
            .filter { $0.entityID != entity.entityID && layout.deviceByEntity[$0.entityID] == device }
            .sortedByName()
    }

    func sibling(of entity: EntityState, deviceClass: String) -> EntityState? {
        siblings(of: entity).first { $0.kind == .sensor && $0.deviceClass == deviceClass && $0.numericState != nil }
    }

    /// The name of the person whose Home Assistant account is `userID`.
    func personName(userID: String) -> String? {
        states.values.first { $0.domain == "person" && $0.attributes["user_id"]?.stringValue == userID }?.name
    }

    /// "Home Assistant", or the integration that provides the entity ("Sonos").
    func source(of entity: EntityState) -> String {
        guard let platform = layout.platformByEntity[entity.entityID],
              let integration = integrations.first(where: { $0.domain == platform }) else { return "Home Assistant" }
        return integration.title
    }
}

// MARK: - Turning off later

/// "Turn off automatically in 30 min" runs on the server, so it happens even if the iPhone is off:
/// one Home Assistant script per device, in `restart` mode so a new delay replaces the previous one.
enum TurnOffTimer {
    static func scriptID(for entity: EntityState) -> String {
        "maison_turn_off_" + entity.entityID.replacingOccurrences(of: ".", with: "_")
    }

    /// When the running timer ends, as remembered on this iPhone.
    static func end(for entity: EntityState) -> Date? {
        let ends = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
        return ends[entity.entityID].flatMap { $0 > .now ? $0 : nil }
    }

    @MainActor
    static func start(_ minutes: Int, for entity: EntityState, in store: HomeStore) async throws {
        if let editor = try await store.configEditor() {
            try await editor.save(.script, id: scriptID(for: entity), config: [
                "alias": .string(String(localized: "Maison: turn off \(entity.name)")),
                "description": .string(String(localized: "Created by the Maison app.")),
                "mode": "restart",
                "icon": "mdi:timer-outline",
                "sequence": [
                    ["delay": ["minutes": "{{ minutes }}"]],
                    ["action": "homeassistant.turn_off", "target": ["entity_id": .string(entity.entityID)]],
                ],
            ])
            // Saving reloads scripts; give the new one a moment to appear.
            try await Task.sleep(for: .milliseconds(600))
        }
        try await store.runScript(scriptID(for: entity), variables: ["minutes": .number(Double(minutes))])
        remember(.now.addingTimeInterval(TimeInterval(minutes * 60)), for: entity)
    }

    @MainActor
    static func cancel(for entity: EntityState, in store: HomeStore) async {
        await store.stopScript(scriptID(for: entity))
        remember(nil, for: entity)
    }

    private static let key = "turnOffTimers"

    private static func remember(_ end: Date?, for entity: EntityState) {
        var ends = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
        ends[entity.entityID] = end
        UserDefaults.standard.set(ends, forKey: key)
    }
}

// MARK: - Never turn off

/// Devices "Turn Everything Off" leaves alone (a fridge, the internet box).
enum NeverTurnOff {
    static let key = "neverTurnOff"

    static func ids(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    static func raw(from ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }
}

extension HomeStore {
    /// What "Turn Everything Off" switches off: lights, plugs, fans and speakers, except protected ones.
    var devicesToTurnOff: [EntityState] {
        let protected = NeverTurnOff.ids(from: UserDefaults.standard.string(forKey: NeverTurnOff.key) ?? "")
        return devices.filter {
            [.light, .switch, .fan, .mediaPlayer].contains($0.kind) && $0.isActive && !protected.contains($0.entityID)
        }
    }

    func turnEverythingOff() async {
        for entity in devicesToTurnOff {
            let service = entity.kind == .mediaPlayer ? "media_pause" : "turn_off"
            await call(entity.domain, service, on: entity)
        }
    }
}

// MARK: - Alerts

/// "Tell me if it stays open more than 30 min": a Home Assistant automation that sends a notification
/// to the phones that have the Home Assistant app, or to Home Assistant's own notifications otherwise.
enum OpenTooLongAlert {
    static func automationID(for entity: EntityState) -> String {
        "maison_open_alert_" + entity.entityID.replacingOccurrences(of: ".", with: "_")
    }

    /// The delay currently set, in minutes, or `nil` when there is no alert.
    @MainActor
    static func minutes(for entity: EntityState, in store: HomeStore) async -> Int? {
        guard let editor = try? await store.configEditor() else { return nil }
        guard let config = try? await editor.load(.automation, id: automationID(for: entity)) else { return nil }
        let trigger = (config["triggers"] ?? config["trigger"])?.arrayValue?.first
        return trigger?["for"]?["minutes"]?.intValue
    }

    @MainActor
    static func set(_ minutes: Int?, for entity: EntityState, in store: HomeStore) async throws {
        guard let editor = try await store.configEditor() else { return }
        let id = automationID(for: entity)
        guard let minutes else {
            try await editor.delete(.automation, id: id)
            return
        }
        let services = await store.notifyServices()
        let phone = services.first { $0.hasPrefix("mobile_app_") } ?? (services.contains("notify") ? "notify" : nil)
        let message = String(localized: "\(entity.name) has been open for \(minutes) min.")
        let action: JSONValue = phone.map {
            ["action": .string("notify.\($0)"), "data": ["title": "Maison", "message": .string(message)]]
        } ?? ["action": "persistent_notification.create", "data": ["title": "Maison", "message": .string(message)]]
        try await editor.save(.automation, id: id, config: [
            "id": .string(id),
            "alias": .string(String(localized: "Maison: \(entity.name) open too long")),
            "description": .string(String(localized: "Created by the Maison app.")),
            "mode": "single",
            "triggers": [["trigger": "state", "entity_id": .string(entity.entityID), "to": "on", "for": ["minutes": .number(Double(minutes))]]],
            "conditions": [],
            "actions": [action],
        ])
    }
}
