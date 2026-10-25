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
}
