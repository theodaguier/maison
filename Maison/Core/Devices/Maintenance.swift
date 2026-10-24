import Foundation

/// Upkeep a device asks for itself: a filter to clean, a battery to change, a problem it reports.
/// Only what a device signals appears, in the room of the device; nothing is guessed from an age.
struct MaintenanceItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Remaining filter life, in percent.
        case filter(remaining: Double)
        /// Battery level, in percent.
        case battery(level: Double)
        /// The device reports a problem.
        case problem
    }

    /// The entity that signals it.
    let id: String
    let kind: Kind
    /// The device that asks: its switch, light or main entity's name.
    let deviceName: String
    let areaID: String?
    /// A button that resets the counter once done ("Filter cleaned").
    let resetButton: String?

    /// Below this, a filter or a battery is worth a word.
    static let threshold = 15.0

    /// Pure: from what each entity reports. `translationKey` is the registry's, the same in every language.
    static func signal(
        entityID: String,
        state: String,
        deviceClass: String?,
        unit: String?,
        translationKey: String?
    ) -> Kind? {
        let key = translationKey ?? ""
        let value = Double(state)
        if deviceClass == "battery", unit == "%", let value, value <= threshold { return .battery(level: value) }
        if entityID.hasPrefix("binary_sensor."), deviceClass == "problem", state == "on" { return .problem }
        if key.contains("filter"), unit == "%", let value, value <= threshold { return .filter(remaining: value) }
        if entityID.hasPrefix("binary_sensor."), key.contains("filter"), state == "on" { return .filter(remaining: 0) }
        return nil
    }
}

/// Upkeep the person marked done: hidden until the device reports a different value.
enum MaintenanceAcknowledgement {
    static let key = "maintenanceDone"

    static func isDone(_ item: MaintenanceItem, state: String, in defaults: UserDefaults = .standard) -> Bool {
        (defaults.dictionary(forKey: key) as? [String: String])?[item.id] == state
    }

    static func markDone(_ item: MaintenanceItem, state: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        all[item.id] = state
        defaults.set(all, forKey: key)
    }
}

extension HomeStore {
    /// Every upkeep a device signals, diagnostic entities included (they are hidden from device lists).
    var maintenanceItems: [MaintenanceItem] {
        states.values.compactMap { entity -> MaintenanceItem? in
            guard let kind = MaintenanceItem.signal(
                entityID: entity.entityID, state: entity.state, deviceClass: entity.deviceClass,
                unit: entity.unit, translationKey: layout.translationKeyByEntity[entity.entityID]
            ) else { return nil }
            let device = layout.deviceByEntity[entity.entityID]
            let siblings = device.map { id in states.values.filter { layout.deviceByEntity[$0.entityID] == id } } ?? []
            let main = siblings.first { !layout.hiddenEntities.contains($0.entityID) && $0.kind != .sensor && $0.kind != .binarySensor }
            let reset = siblings.first { $0.domain == "button" && (layout.translationKeyByEntity[$0.entityID] ?? "").contains("filter") }
            let item = MaintenanceItem(
                id: entity.entityID, kind: kind, deviceName: main?.name ?? entity.name,
                areaID: layout.areaByEntity[entity.entityID] ?? main.flatMap { layout.areaByEntity[$0.entityID] },
                resetButton: reset?.entityID
            )
            return MaintenanceAcknowledgement.isDone(item, state: entity.state) ? nil : item
        }
        .sorted { $0.id < $1.id }
    }

    func maintenance(in area: Area) -> [MaintenanceItem] {
        maintenanceItems.filter { $0.areaID == area.id }
    }

    /// "C'est fait": resets the device's counter when it has a button for it, and hides the item until
    /// the device reports something new.
    func markDone(_ item: MaintenanceItem) async {
        if let button = item.resetButton, let entity = states[button] {
            await call("button", "press", on: entity)
        }
        if let state = states[item.id]?.state {
            MaintenanceAcknowledgement.markDone(item, state: state)
        }
    }
}
