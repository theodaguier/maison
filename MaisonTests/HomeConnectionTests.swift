import Foundation
@testable import Maison
import Testing

/// How `HomeStore` keeps its connection to Home Assistant: updates, reconnection, the last known home.
@MainActor
struct HomeConnectionTests {
    let power: JSONValue = ["sensor.power": ["s": "100", "a": ["unit_of_measurement": "W"], "lc": 1_792_483_923]]

    // MARK: - Updates

    @Test func loadsTheHomeFromOneEntitySubscription() async throws {
        let server = fakeHomeServer(entities: power)
        let store = try FakeHome.store([server])

        await store.connect()

        #expect(store.phase == .connected)
        #expect(store.states["sensor.power"]?.state == "100")
        #expect(await server.sentMessages(ofType: "subscribe_entities").count == 1)
        #expect(await server.sentMessages(ofType: "get_states").isEmpty)
        #expect(await server.sentMessages(ofType: "subscribe_events").isEmpty)
    }

    @Test func appliesUpdatesTogetherOnceTheBatchWindowCloses() async throws {
        let server = fakeHomeServer(entities: power)
        let store = try FakeHome.store([server], timing: ConnectionTiming(batchWindow: .milliseconds(300)))
        await store.connect()
        let changes = StatesChanges(store)

        // A power sensor reporting many times within the window.
        for watts in 101...150 {
            await server.pushEntities(["c": ["sensor.power": ["+": ["s": .string("\(watts)"), "lc": 1_792_483_980]]]])
        }
        #expect(store.states["sensor.power"]?.state == "100")

        try await waitUntil { store.states["sensor.power"]?.state == "150" }
        try await Task.sleep(for: .milliseconds(400))
        #expect(changes.count == 1)
    }

    @Test func aSensorReportingTheSameValueRedrawsNothing() async throws {
        let server = fakeHomeServer(entities: power)
        let store = try FakeHome.store([server], timing: ConnectionTiming(batchWindow: .milliseconds(50)))
        await store.connect()
        let connectedAt = try #require(store.lastUpdate)
        let changes = StatesChanges(store)

        await server.pushEntities(["c": ["sensor.power": ["+": ["lu": 1_792_483_990]]]])

        try await waitUntil { store.lastUpdate.map { $0 > connectedAt } ?? false }
        try await Task.sleep(for: .milliseconds(100))
        #expect(changes.count == 0)
        #expect(store.states["sensor.power"]?.state == "100")
    }

    @Test func removesAnEntityTheServerRemoved() async throws {
        let server = fakeHomeServer(entities: power)
        let store = try FakeHome.store([server], timing: ConnectionTiming(batchWindow: .milliseconds(20)))
        await store.connect()

        await server.pushEntities(["r": ["sensor.power"]])

        try await waitUntil { store.states.isEmpty }
    }

    // MARK: - Reconnection

    @Test func reconnectsWhenTheServerStopsAnsweringPings() async throws {
        let opened = Log<URL>()
        let store = try FakeHome.store(
            [fakeHomeServer(entities: power, answersPings: false), fakeHomeServer(entities: power)],
            timing: ConnectionTiming(heartbeat: .milliseconds(50), pingTimeout: .milliseconds(50), retryDelay: .milliseconds(300)),
            opened: opened
        )
        await store.connect()
        #expect(store.phase == .connected)

        try await waitUntil {
            if case .offline = store.phase { true } else { false }
        }
        #expect(store.states["sensor.power"]?.state == "100")
        try await waitUntil { opened.values.count == 2 && store.phase == .connected }
        try await waitUntil { !store.latencies.isEmpty }
    }

    @Test func checksTheConnectionWhenTheAppReturnsToTheForeground() async throws {
        let opened = Log<URL>()
        let store = try FakeHome.store(
            [fakeHomeServer(entities: power, answersPings: false), fakeHomeServer(entities: power)],
            timing: ConnectionTiming(heartbeat: .seconds(3600), pingTimeout: .milliseconds(50), retryDelay: .seconds(3600)),
            opened: opened
        )
        await store.connect()

        await store.becameActive()

        #expect(opened.values.count == 2)
        #expect(store.phase == .connected)
    }

    @Test func keepsAConnectionThatStillAnswers() async throws {
        let opened = Log<URL>()
        let store = try FakeHome.store([fakeHomeServer(entities: power)], timing: ConnectionTiming(heartbeat: .seconds(3600)), opened: opened)
        await store.connect()

        await store.becameActive()

        #expect(opened.values.count == 1)
        #expect(store.latencies.count == 1)
        #expect(store.phase == .connected)
    }

    @Test func triesAgainAtOnceWhenTheAppReturnsAfterAFailure() async throws {
        let store = try FakeHome.store(
            [FailingTransport(), fakeHomeServer(entities: power)],
            timing: ConnectionTiming(heartbeat: .seconds(3600), retryDelay: .seconds(3600))
        )
        await store.connect()
        guard case .failed = store.phase else {
            Issue.record("Expected a failure, got \(store.phase)")
            return
        }

        await store.becameActive()

        #expect(store.phase == .connected)
    }

    @Test func reconnectsWhenTheNetworkChanges() async throws {
        let opened = Log<URL>()
        let store = try FakeHome.store(
            [fakeHomeServer(entities: power), fakeHomeServer(entities: power)],
            timing: ConnectionTiming(heartbeat: .seconds(3600), retryDelay: .milliseconds(50)),
            opened: opened
        )
        await store.connect()
        let previous = try #require(store.connection)

        await store.networkChanged()

        #expect(opened.values.count == 2)
        #expect(store.phase == .connected)
        #expect(store.connection !== previous)
        await #expect(throws: HomeAssistantError.connectionClosed) {
            try await previous.send(["type": "ping"])
        }
        // The previous connection closing is not a lost connection: no other attempt follows.
        try await Task.sleep(for: .milliseconds(200))
        #expect(opened.values.count == 2)
        #expect(store.phase == .connected)
    }

    @Test func givesUpOnAServerThatStopsAnsweringWhileLoading() async throws {
        // The subscription is accepted, but the states never follow.
        let stalled = FakeTransport { message in
            message["type"]?.stringValue == "auth" ? [["type": "auth_ok"]] : message["type"]?.stringValue == "subscribe_entities" ? [result(for: message)] : [result(for: message, [])]
        }
        let opened = Log<URL>()
        let store = try FakeHome.store(
            [stalled, fakeHomeServer(entities: power)],
            timing: ConnectionTiming(retryDelay: .seconds(3600), loadTimeout: .milliseconds(100)),
            opened: opened
        )

        await store.connect()
        guard case .failed = store.phase else {
            Issue.record("Expected a failure, got \(store.phase)")
            return
        }

        // The attempt that stalled doesn't block the next one.
        await store.connect()
        #expect(opened.values.count == 2)
        #expect(store.phase == .connected)
    }

    @Test(arguments: [
        (NetworkRoute(isReachable: false), NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.1.1"]), true),
        (NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.1.1"]), NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.1.1"]), false),
        (NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.1.1"]), NetworkRoute(isReachable: true, interfaces: ["pdp_ip0"], gateways: ["10.0.0.1"]), true),
        (NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.1.1"]), NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.0.254"]), true),
        (NetworkRoute(isReachable: true, interfaces: ["en0"], gateways: ["192.168.1.1"]), NetworkRoute(isReachable: false), false),
    ])
    func reconnectsOnlyWhenAnotherNetworkIsReached(previous: NetworkRoute, current: NetworkRoute, reconnects: Bool) {
        #expect(current.isChange(from: previous) == reconnects)
    }
}
