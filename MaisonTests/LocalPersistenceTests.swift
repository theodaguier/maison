import Foundation
@testable import Maison
import Testing

/// On-device persistence before GRDB.
///
/// Credentials and the presence webhook are JSON in the keychain (`CredentialStore.load` and
/// `KeychainWebhookStorage.load` both `JSONDecoder().decode`). Favourites and the floor plan are
/// `UserDefaults`. Nothing versions those bytes: a new optional field is the only change the
/// current readers still accept. GRDB is the target store. Tests that register a `DatabaseMigrator`,
/// migrate an empty database, and migrate a database created at each earlier `userVersion` belong
/// with that move; this harness is the stand-in until then.
enum LocalPersistenceHarness {
    static let favoritesKey = "favoriteEntityIDs"
    static let floorPlanKey = "floorPlan"
    static let presenceKey = "presenceEnabled"
    /// Written through `UserDefaults.standard` by `TurnOffTimer`, so a suite cannot intercept it.
    static let turnOffTimersKey = "turnOffTimers"

    /// Every document shape the current readers accept, oldest first. Version 0 is the empty store.
    static let documents: [Document] = [
        Document(fixture: "credentials-v1", version: 1),
        Document(fixture: "credentials-v2", version: 2),
        Document(fixture: "webhook-v1", version: 1),
        Document(fixture: "webhook-v2", version: 2),
        Document(fixture: "floor-plan-v1", version: 1),
        Document(fixture: "floor-plan-v2", version: 2),
        Document(fixture: "favorites-v1", version: 1),
    ]

    struct Document: Sendable, CustomTestStringConvertible {
        var fixture: String
        var version: Int
        var testDescription: String { "\(fixture) (schema \(version))" }
    }

    static let directory = "Fixtures/Persistence"
    static let local = URL(string: "http://homeassistant.local:8123")!
    static let remote = URL(string: "https://maison.example.com")!
    static let credentialExpiry = Date(timeIntervalSinceReferenceDate: 821_692_800)
    static let scannedAt = Date(timeIntervalSinceReferenceDate: 781_692_800)

    static func suite() -> UserDefaults {
        let name = "LocalPersistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func data(_ fixture: String) throws -> Data {
        try RecordedFixture.data(fixture, directory: directory)
    }
}

@MainActor
struct LocalPersistenceTests {
    @Test func anEmptyStoreReadsAsEmpty() throws {
        let defaults = LocalPersistenceHarness.suite()
        for key in [
            LocalPersistenceHarness.favoritesKey,
            LocalPersistenceHarness.floorPlanKey,
            LocalPersistenceHarness.presenceKey,
            LocalPersistenceHarness.turnOffTimersKey,
            NeverTurnOff.key,
        ] {
            #expect(defaults.object(forKey: key) == nil)
        }

        let store = HouseholdStore(cloud: nil, defaults: defaults)
        #expect(store.status == .unavailable)
        #expect(store.favoriteIDs.isEmpty)
        #expect(store.floorPlan == nil)
        #expect(store.household == nil)

        let presence = PresenceReporter(
            webhooks: MemoryWebhookStorage(),
            credentialStore: MemoryCredentialStorage(),
            defaults: defaults
        )
        #expect(!presence.isEnabled)
        #expect(try MemoryCredentialStorage().load() == nil)
        #expect(NeverTurnOff.ids(from: defaults.string(forKey: NeverTurnOff.key) ?? "").isEmpty)
        #expect(NeverTurnOff.ids(from: NeverTurnOff.raw(from: ["switch.fridge", "switch.box"])) == Set(["switch.box", "switch.fridge"]))
    }

    /// Opens each stored shape with the readers the app uses today.
    @Test(arguments: LocalPersistenceHarness.documents)
    func storedDocumentSurvives(_ document: LocalPersistenceHarness.Document) async throws {
        let data = try LocalPersistenceHarness.data(document.fixture)
        switch document.fixture {
        case "credentials-v1":
            try expectCredentials(data, token: "access-v1", refresh: "refresh-v1", remote: nil)
        case "credentials-v2":
            try expectCredentials(data, token: "access-v2", refresh: "refresh-v2", remote: LocalPersistenceHarness.remote)
        case "webhook-v1":
            try expectWebhook(data, cloudhook: nil, defaults: LocalPersistenceHarness.suite())
        case "webhook-v2":
            try expectWebhook(data, cloudhook: URL(string: "https://hooks.nabu.casa/wh-abc"), defaults: LocalPersistenceHarness.suite())
        case "floor-plan-v1":
            try await expectFloorPlan(data, scannedBy: nil, defaults: LocalPersistenceHarness.suite())
        case "floor-plan-v2":
            try await expectFloorPlan(data, scannedBy: "Théo", defaults: LocalPersistenceHarness.suite())
        case "favorites-v1":
            let ids = try JSONDecoder().decode([String].self, from: data)
            let defaults = LocalPersistenceHarness.suite()
            defaults.set(ids, forKey: LocalPersistenceHarness.favoritesKey)
            #expect(ids == ["light.salon", "lock.porte"])
            #expect(HouseholdStore(cloud: nil, defaults: defaults).favoriteIDs == ids)
        default:
            Issue.record(Comment(rawValue: "No reader for \(document.fixture)"))
        }
    }

    @Test func aDemoWebhookFromEarlierBuildsIsDropped() throws {
        let webhook = try JSONDecoder().decode(Webhook.self, from: LocalPersistenceHarness.data("webhook-v1-demo"))
        #expect(webhook.isDemo)
        let defaults = LocalPersistenceHarness.suite()
        defaults.set(true, forKey: LocalPersistenceHarness.presenceKey)
        let storage = MemoryWebhookStorage(webhook)

        let presence = PresenceReporter(webhooks: storage, credentialStore: MemoryCredentialStorage(), defaults: defaults)

        #expect(storage.load() == nil)
        #expect(!presence.isEnabled)
        #expect(!defaults.bool(forKey: LocalPersistenceHarness.presenceKey))
    }

    /// `HouseholdStore` drops a plan it cannot decode (`try?`), so a missing `devices` key must not fail.
    @Test func aFloorPlanWrittenWithoutDevicesStillLoads() throws {
        let data = try LocalPersistenceHarness.data("floor-plan-missing-devices")
        let plan = try JSONDecoder().decode(FloorPlan.self, from: data)
        #expect(plan.devices.isEmpty)
        #expect(!plan.rooms.isEmpty)

        let defaults = LocalPersistenceHarness.suite()
        defaults.set(data, forKey: LocalPersistenceHarness.floorPlanKey)
        #expect(HouseholdStore(cloud: nil, defaults: defaults).floorPlan == plan)
    }

    private func expectCredentials(_ data: Data, token: String, refresh: String, remote: URL?) throws {
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        #expect(credentials.serverURL == LocalPersistenceHarness.local)
        #expect(credentials.accessToken == token)
        #expect(credentials.refreshToken == refresh)
        #expect(credentials.expiresAt == LocalPersistenceHarness.credentialExpiry)
        #expect(credentials.remoteURL == remote)
        #expect(credentials.addresses == [LocalPersistenceHarness.local] + (remote.map { [$0] } ?? []))
        #expect(!credentials.isExpired(at: credentials.expiresAt.addingTimeInterval(-61)))

        let storage = MemoryCredentialStorage()
        try storage.save(credentials)
        #expect(try storage.load() == credentials)
        let rewritten = try JSONEncoder().encode(credentials)
        #expect(try JSONDecoder().decode(Credentials.self, from: rewritten) == credentials)
    }

    private func expectWebhook(_ data: Data, cloudhook: URL?, defaults: UserDefaults) throws {
        let webhook = try JSONDecoder().decode(Webhook.self, from: data)
        #expect(webhook.id == "wh-abc")
        #expect(webhook.localURL == LocalPersistenceHarness.local)
        #expect(webhook.remoteURL == LocalPersistenceHarness.remote)
        #expect(webhook.cloudhookURL == cloudhook)
        #expect(!webhook.isDemo)
        var endpoints = [
            "http://homeassistant.local:8123/api/webhook/wh-abc",
            "https://maison.example.com/api/webhook/wh-abc",
        ]
        if let cloudhook { endpoints.append(cloudhook.absoluteString) }
        #expect(webhook.endpoints(addresses: nil).map(\.absoluteString) == endpoints)

        let storage = MemoryWebhookStorage(webhook)
        defaults.set(true, forKey: LocalPersistenceHarness.presenceKey)
        let presence = PresenceReporter(webhooks: storage, credentialStore: MemoryCredentialStorage(), defaults: defaults)
        #expect(presence.isEnabled)
        #expect(storage.load() == webhook)
        #expect(try JSONDecoder().decode(Webhook.self, from: JSONEncoder().encode(webhook)) == webhook)
    }

    private func expectFloorPlan(_ data: Data, scannedBy: String?, defaults: UserDefaults) async throws {
        defaults.set(data, forKey: LocalPersistenceHarness.floorPlanKey)
        let store = HouseholdStore(cloud: nil, defaults: defaults)
        let plan = try #require(store.floorPlan)
        let room = try #require(plan.rooms.first)
        #expect(plan.scannedBy == scannedBy)
        #expect(plan.scannedAt == LocalPersistenceHarness.scannedAt)
        #expect(plan.rooms.map(\.name) == ["Salon"])
        #expect(room.areaID == "salon")
        #expect(room.surface == 12.0)
        #expect(plan.devices["light.salon"] == FloorPlan.Point(x: 1.5, y: 2.25))
        #expect(plan.objects.map(\.category) == ["sofa"])
        #expect(plan.windows.count == 1)
        #expect(plan.walls.count == 1)

        try await store.saveFloorPlan(plan)
        #expect(HouseholdStore(cloud: nil, defaults: defaults).floorPlan == plan)
    }
}
