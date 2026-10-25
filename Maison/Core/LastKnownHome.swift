import Foundation

/// The home as it was last seen, kept on this iPhone: starting away from any network shows it, with
/// the time it dates from, instead of an error. Only the states and the rooms, never a history.
struct LastKnownHome: Sendable, Equatable {
    var serverURL: URL
    /// When the states were last received from the server.
    var savedAt: Date
    var states: [String: EntityState]
    var layout: HomeLayout
}

extension LastKnownHome: Codable {
    private enum CodingKeys: String, CodingKey {
        case serverURL, savedAt, states, layout
    }

    /// `EntityState` decodes Home Assistant's own format, whose dates are text; here they stay exact.
    private struct SavedState: Codable {
        var entityID: String
        var state: String
        var attributes: [String: JSONValue]
        var lastChanged: Date?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(URL.self, forKey: .serverURL)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        layout = try container.decode(HomeLayout.self, forKey: .layout)
        let saved = try container.decode([SavedState].self, forKey: .states)
        states = Dictionary(saved.map { state in
            (state.entityID, EntityState(entityID: state.entityID, state: state.state, attributes: state.attributes, lastChanged: state.lastChanged))
        }, uniquingKeysWith: { _, last in last })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(layout, forKey: .layout)
        try container.encode(states.values.map { state in
            SavedState(entityID: state.entityID, state: state.state, attributes: state.attributes, lastChanged: state.lastChanged)
        }, forKey: .states)
    }
}

protocol LastKnownHomeStorage: Sendable {
    func load() -> LastKnownHome?
    func save(_ home: LastKnownHome) async
    func delete() async
}

/// A JSON file in Application Support, left out of backups: the server holds the same data.
/// A file that can't be read, from an older shape or cut short, counts as no home at all.
actor LastKnownHomeFile: LastKnownHomeStorage {
    nonisolated let url: URL

    init(url: URL) {
        self.url = url
    }

    static func onDevice() -> LastKnownHomeFile {
        LastKnownHomeFile(url: .applicationSupportDirectory.appending(path: "LastKnownHome.json"))
    }

    nonisolated func load() -> LastKnownHome? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LastKnownHome.self, from: data)
    }

    func save(_ home: LastKnownHome) {
        do {
            let data = try JSONEncoder().encode(home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            var file = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        } catch {
            // The next save tries again; the home on the server is unaffected.
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
