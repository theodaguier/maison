import Foundation

/// One message of `subscribe_entities`: Home Assistant's compressed form of entity states.
///
/// The first message lists every entity (`a`); each later one carries what changed (`c`), with
/// only the fields that moved, and the entities that went away (`r`).
struct EntityUpdate: Sendable, Equatable {
    /// Entities sent in full: all of them in the first message, new ones afterwards.
    var added: [String: EntityState] = [:]
    var changed: [String: Diff] = [:]
    var removed: [String] = []

    /// The fields of one entity that changed.
    struct Diff: Sendable, Equatable {
        var state: String?
        /// Attributes added or changed; the others keep their value.
        var attributes: [String: JSONValue] = [:]
        var removedAttributes: [String] = []
        var lastChanged: Date?
    }

    init(added: [String: EntityState] = [:], changed: [String: Diff] = [:], removed: [String] = []) {
        self.added = added
        self.changed = changed
        self.removed = removed
    }

    init(event: JSONValue) {
        for (entityID, compressed) in event["a"]?.objectValue ?? [:] {
            added[entityID] = EntityState(
                entityID: entityID,
                state: compressed["s"]?.stringValue ?? "unknown",
                attributes: compressed["a"]?.objectValue ?? [:],
                lastChanged: Self.date(compressed["lc"] ?? compressed["lu"])
            )
        }
        for (entityID, change) in event["c"]?.objectValue ?? [:] {
            let plus = change["+"]
            changed[entityID] = Diff(
                state: plus?["s"]?.stringValue,
                attributes: plus?["a"]?.objectValue ?? [:],
                removedAttributes: change["-"]?["a"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                lastChanged: Self.date(plus?["lc"])
            )
        }
        removed = event["r"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    /// Applies the message to `states`; `true` when something the app shows changed. A diff that only
    /// moves `last_updated` (a sensor reporting the same value) changes nothing.
    @discardableResult
    func apply(to states: inout [String: EntityState]) -> Bool {
        var didChange = false
        for (entityID, state) in added where states[entityID] != state {
            states[entityID] = state
            didChange = true
        }
        for (entityID, diff) in changed {
            guard let current = states[entityID] else { continue }
            var attributes = current.attributes.merging(diff.attributes) { _, new in new }
            diff.removedAttributes.forEach { attributes.removeValue(forKey: $0) }
            let updated = EntityState(
                entityID: entityID,
                state: diff.state ?? current.state,
                attributes: attributes,
                lastChanged: diff.lastChanged ?? current.lastChanged
            )
            if updated != current {
                states[entityID] = updated
                didChange = true
            }
        }
        for entityID in removed where states.removeValue(forKey: entityID) != nil {
            didChange = true
        }
        return didChange
    }

    /// Compressed states carry Unix timestamps in seconds.
    private static func date(_ value: JSONValue?) -> Date? {
        value?.doubleValue.map { Date(timeIntervalSince1970: $0) }
    }
}

extension HomeAssistantConnection {
    /// Subscribes to `subscribe_entities`: returns every entity as it is now, then streams what changes.
    func entities() async throws -> (states: [String: EntityState], updates: AsyncStream<EntityUpdate>) {
        let events = try await subscribe(["type": "subscribe_entities"])
        let (updates, continuation) = AsyncStream<EntityUpdate>.makeStream()
        let first: EntityUpdate = try await withCheckedThrowingContinuation { first in
            let task = Task {
                var isFirst = true
                for await event in events {
                    let update = EntityUpdate(event: event)
                    if isFirst {
                        isFirst = false
                        first.resume(returning: update)
                    } else {
                        continuation.yield(update)
                    }
                }
                if isFirst {
                    first.resume(throwing: HomeAssistantError.connectionClosed)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        var states: [String: EntityState] = [:]
        first.apply(to: &states)
        return (states, updates)
    }
}
