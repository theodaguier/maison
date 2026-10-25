import Foundation
@testable import Maison
import Observation
import Testing

/// A Home Assistant that answers everything `HomeStore.connect()` asks: `entities` is the first
/// `subscribe_entities` message, registries and server details are empty.
func fakeHomeServer(entities: JSONValue = [:], answersPings: Bool = true) -> FakeTransport {
    FakeTransport { message in
        switch message["type"]?.stringValue {
        case "auth":
            return [["type": "auth_ok", "ha_version": "2026.8.1"]]
        case "subscribe_entities":
            return [result(for: message), ["id": message["id"] ?? .null, "type": "event", "event": ["a": entities]]]
        case "ping":
            return answersPings ? [["id": message["id"] ?? .null, "type": "pong"]] : []
        default:
            return [result(for: message, [])]
        }
    }
}

extension FakeTransport {
    /// Sends a `subscribe_entities` message to the app, as the server does when entities change.
    func pushEntities(_ event: JSONValue) {
        guard let id = sentMessages(ofType: "subscribe_entities").last?["id"] else { return }
        push(["id": id, "type": "event", "event": event])
    }
}

enum FakeHome {
    static let server = URL(string: "http://homeassistant.local:8123")!
    static let credentials = Credentials(serverURL: server, accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)

    /// A signed-in store whose connections go, one after the other, through `transports`.
    /// Once they run out, the last one is used again. `opened` counts the connections.
    @MainActor
    static func store(
        _ transports: [any WebSocketTransport],
        timing: ConnectionTiming = ConnectionTiming(),
        opened: Log<URL> = Log()
    ) throws -> HomeStore {
        let defaults = UserDefaults(suiteName: "FakeHome.\(UUID().uuidString)")!
        let keychain = MemoryCredentialStorage()
        try keychain.save(credentials)
        let connector = ServerConnector(open: { address, token in
            let index = opened.values.count
            opened.append(address)
            return HomeAssistantConnection(transport: transports[min(index, transports.count - 1)], accessToken: token)
        })
        return HomeStore(
            credentialStore: keychain, defaults: defaults,
            household: HouseholdStore(cloud: nil, defaults: defaults),
            presence: PresenceReporter(webhooks: MemoryWebhookStorage(), defaults: defaults),
            connector: connector,
            timing: timing
        )
    }
}

/// Waits until `condition` holds, recording an issue after `timeout`.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(3),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Counts the changes of `store.states` that would redraw a screen reading it.
@MainActor
final class StatesChanges {
    private(set) var count = 0
    private let store: HomeStore

    init(_ store: HomeStore) {
        self.store = store
        track()
    }

    private func track() {
        withObservationTracking {
            _ = store.states
        } onChange: {
            Task { @MainActor in
                self.count += 1
                self.track()
            }
        }
    }
}
