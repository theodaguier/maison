import Foundation

/// One slot of the + panel: an action of Maison, or a device, a scene or a rule the person pinned.
enum Shortcut: Codable, Hashable, Identifiable, Sendable {
    case action(PlusAction)
    /// A device, a scene (`scene.`) or a rule (`automation.`), by entity id.
    case entity(String)

    var id: String {
        switch self {
        case .action(let action): "action:\(action.rawValue)"
        case .entity(let entityID): "entity:\(entityID)"
        }
    }
}

/// The person's shortcuts, kept on this iPhone: twelve at most, six to a page.
enum ShortcutList {
    static let key = "plusShortcuts"
    static let capacity = 12
    static let perPage = 6

    static func load(from defaults: UserDefaults = .standard) -> [Shortcut]? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) }
    }

    static func save(_ shortcuts: [Shortcut], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(Array(shortcuts.prefix(capacity))), forKey: key)
    }

    /// The first set, as in the mock-up: Maison's actions, then the household's first favourites.
    static func starting(favorites: [String]) -> [Shortcut] {
        let actions: [PlusAction] = [.describeRule, .leaving, .scene, .addDevice, .newRule, .turnOff, .testInternet, .search]
        let pinned = favorites.prefix(capacity - actions.count - 1).map(Shortcut.entity)
        return actions.map(Shortcut.action) + pinned
    }

    /// Splits into pages of six.
    static func pages<T>(_ items: [T]) -> [[T]] {
        stride(from: 0, to: items.count, by: perPage).map { Array(items[$0..<min($0 + perPage, items.count)]) }
    }
}
