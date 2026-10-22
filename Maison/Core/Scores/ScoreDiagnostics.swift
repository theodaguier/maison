#if DEBUG
import Foundation

extension HomeStore {
    /// Debug builds only: what the scores found, written to the app's Documents so it can be read from a Mac
    /// (`xcrun devicectl device copy from … --domain-type appDataContainer`). Entity ids and counts, no values of the home.
    func writeScoreDiagnostics(_ scores: HomeScores, duration: Duration) async {
        let weekAgo = Date.now.addingTimeInterval(-8 * 86_400)
        var meters: [[String: Any]] = []
        for meter in await electricityMeters().ids {
            let points = await statistics(of: meter, since: weekAgo, period: "hour")
            meters.append(["id": meter, "hourlyPoints": points.count, "withChange": points.count { $0.change != nil }])
        }
        var sensors: [[String: Any]] = []
        for (area, sensor) in roomTemperatureSensors {
            let points = await statistics(of: sensor.entityID, since: weekAgo, period: "hour")
            let history = await changes(of: sensor.entityID, since: weekAgo)
            sensors.append([
                "room": area.id, "id": sensor.entityID, "statistics": points.count, "history": history.count,
                "stateClass": sensor.attributes["state_class"]?.stringValue ?? "none",
            ])
        }
        let temperature = devices.filter { $0.deviceClass == "temperature" }
        let registry = (try? await registryEntries()) ?? []
        let pingRegistry = registry.filter { $0["platform"]?.stringValue == "ping" }.map { entry in
            "\(entry["entity_id"]?.stringValue ?? "?") disabled=\(entry["disabled_by"]?.stringValue ?? "no") key=\(entry["translation_key"]?.stringValue ?? "none") keys=\(entry.objectValue?.keys.sorted().joined(separator: ",") ?? "")"
        }
        let report: [String: Any] = [
            "date": Date.now.ISO8601Format(),
            "durationSeconds": Double(duration.components.seconds),
            "phase": String(describing: phase),
            "states": states.count,
            "rooms": rooms.map(\.id),
            "temperatureEntities": temperature.map { ["id": $0.entityID, "room": layout.areaByEntity[$0.entityID] ?? "none", "indoor": indoorTemperatureSensors.contains($0)] },
            "roomTemperatureSensors": sensors,
            "enteredRange": ComfortRangeSetting.range().map { "\($0)" } ?? "none",
            "electricityMeters": meters,
            "energyEntities": devices.filter { $0.deviceClass == "energy" }.map { "\($0.entityID) \($0.attributes["state_class"]?.stringValue ?? "none")" },
            "pingEntities": states.values.filter { layout.platformByEntity[$0.entityID] == "ping" }.map(\.entityID),
            "connectivityEntities": states.values.filter { $0.deviceClass == "connectivity" }.map { "\($0.entityID) \(layout.platformByEntity[$0.entityID] ?? "?")" },
            "comfort": scores.comfort.map { "\($0.percent) % over \($0.rooms.count) rooms, range \($0.range)" } ?? "none",
            "energy": scores.energy.map { "today \($0.today), usual \($0.usual.map { "\($0)" } ?? "none"), \($0.lastDay.count) hours" } ?? "none",
            "network": scores.network.map { "\($0.percent) %" } ?? "none",
            "domains": Dictionary(grouping: states.values, by: \.domain).mapValues(\.count),
            "deviceClasses": Dictionary(grouping: states.values.compactMap(\.deviceClass), by: { $0 }).mapValues(\.count),
            "platforms": Dictionary(grouping: layout.platformByEntity.values, by: { $0 }).mapValues(\.count),
            "climateWithTemperature": devices.filter { $0.kind == .climate && $0.currentTemperature != nil }.count,
            "weather": states.values.filter { $0.domain == "weather" }.count,
            "pingRegistry": pingRegistry,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: folder.appending(path: "score-diagnostics.json"))
    }
}
#endif
