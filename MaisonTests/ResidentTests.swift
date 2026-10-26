import Foundation
@testable import Maison
import Testing

/// A resident's path: requests to an administrator instead of actions that fail, and the sign-out that
/// takes Maison's registration away with it.
struct AdministratorRequestTests {
    @Test func leavesANotificationEveryAccountMayWrite() {
        let command = AdministratorRequest.rules.command(from: "Léa")

        #expect(command["type"]?.stringValue == "call_service")
        #expect(command["domain"]?.stringValue == "persistent_notification")
        #expect(command["service"]?.stringValue == "create")
        #expect(command["service_data"]?["notification_id"]?.stringValue == "maison_request_rules")
        #expect(command["service_data"]?["message"]?.stringValue?.contains("Léa") == true)
    }

    @Test func oneNotificationPerRequest() {
        let timer = AdministratorRequest.turnOffTimer(entityID: "switch.radiateur", name: "Radiateur")
        #expect(timer.notificationID == "maison_request_timer_switch.radiateur")
        #expect(timer.notificationID != AdministratorRequest.openingAlert(entityID: "switch.radiateur", name: "Radiateur").notificationID)
        #expect(timer.message(from: "Léa").contains("Radiateur"))
    }

    @Test func aLinkRequestCarriesWhatTheAdministratorsMaisonNeeds() throws {
        let id = AdministratorRequest.linkTracker(tracker: "device_tracker.iphone_de_lea", userID: "u42").notificationID

        let request = try #require(AdministratorRequest.linkRequest(notificationID: id))
        #expect(request.tracker == "device_tracker.iphone_de_lea")
        #expect(request.userID == "u42")
        #expect(AdministratorRequest.linkRequest(notificationID: "maison_request_rules") == nil)
        #expect(AdministratorRequest.linkRequest(notificationID: "maison_link:u42:light.lampe") == nil)
    }
}

@MainActor
struct ResidentPathTests {
    let webhook = Webhook(id: "hook1", localURL: FakeHome.server, remoteURL: nil)

    private func server(isAdmin: Bool, replies: [String: JSONValue] = [:], entities: JSONValue = [:]) -> FakeTransport {
        var all: [String: JSONValue] = [
            "auth/current_user": ["id": "u42", "name": "Léa", "is_admin": .bool(isAdmin)],
            "config/entity_registry/list": [
                ["entity_id": "device_tracker.iphone_de_lea", "platform": "mobile_app", "unique_id": "hook1", "config_entry_id": "entry-maison"],
                ["entity_id": "sensor.iphone_de_lea_battery", "platform": "mobile_app", "unique_id": "hook1_battery", "config_entry_id": "entry-maison"],
            ],
            "person/list": ["storage": [["id": "lea", "user_id": "u42", "device_trackers": []]]],
        ]
        all.merge(replies) { _, new in new }
        return fakeHomeServer(entities: entities, replies: all)
    }

    private func connected(_ transport: FakeTransport, http: any HTTPClient = URLSessionHTTPClient(), webhooks: MemoryWebhookStorage = MemoryWebhookStorage()) async throws -> HomeStore {
        let store = try FakeHome.store([transport], webhooks: webhooks, http: http)
        await store.connect()
        try await waitUntil { store.currentUser != nil }
        return store
    }

    @Test func aResidentAsksAnAdministrator() async throws {
        let transport = server(isAdmin: false)
        let store = try await connected(transport)
        #expect(store.isResident)

        try await store.ask(.rules)

        let calls = await transport.sentMessages(ofType: "call_service")
        #expect(calls.map { $0["service_data"]?["notification_id"]?.stringValue } == ["maison_request_rules"])
        #expect(calls.first?["service_data"]?["message"]?.stringValue?.contains("Léa") == true)
    }

    @Test func aResidentsIPhoneWaitsForAnAdministratorInsteadOfFailingSilently() async throws {
        let transport = server(isAdmin: false)
        let store = try await connected(transport)

        let link = try await store.attachTracker(webhookID: "hook1")

        #expect(link == .needsAdministrator(.linkTracker(tracker: "device_tracker.iphone_de_lea", userID: "u42")))
        #expect(await transport.sentMessages(ofType: "person/update").isEmpty)
    }

    @Test func theLocationSwitchSaysWhenTheIPhoneDoesntCountYet() async throws {
        let webhooks = MemoryWebhookStorage(webhook)
        let store = try await connected(server(isAdmin: false), webhooks: webhooks)

        await store.presence.link(with: store)

        #expect(store.presence.trackerLink == .needsAdministrator(.linkTracker(tracker: "device_tracker.iphone_de_lea", userID: "u42")))
    }

    @Test func aRefusedLinkIsShownNotSwallowed() async throws {
        let refusing = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": return [["type": "auth_ok", "ha_version": "2026.8.1"]]
            case "subscribe_entities": return [result(for: message), ["id": message["id"] ?? .null, "type": "event", "event": ["a": [:]]]]
            case "auth/current_user": return [result(for: message, ["id": "u42", "name": "Théo", "is_admin": true])]
            case "person/list": return [["id": message["id"] ?? .null, "type": "result", "success": false, "error": ["code": "unauthorized", "message": "Unauthorized"]]]
            case "config/entity_registry/list":
                return [result(for: message, [["entity_id": "device_tracker.iphone", "platform": "mobile_app", "unique_id": "hook1"]])]
            default: return [result(for: message, [])]
            }
        }
        let store = try await connected(refusing, webhooks: MemoryWebhookStorage(webhook))

        await store.presence.link(with: store)

        #expect(store.presence.trackerLink == .failed)
    }

    @Test func anAdministratorLinksTheTrackerToTheirPerson() async throws {
        let transport = server(isAdmin: true)
        let store = try await connected(transport)

        let link = try await store.attachTracker(webhookID: "hook1")

        #expect(link == .linked)
        let updates = await transport.sentMessages(ofType: "person/update")
        #expect(updates.map { $0["device_trackers"]?.arrayValue?.compactMap(\.stringValue) } == [["device_tracker.iphone_de_lea"]])
    }

    @Test func anAdministratorsMaisonDoesWhatResidentsAskedFor() async throws {
        let request = AdministratorRequest.linkTracker(tracker: "device_tracker.iphone_de_lea", userID: "u42")
        let transport = server(isAdmin: true, replies: [
            "persistent_notification/get": [
                ["notification_id": .string(request.notificationID), "title": "Maison", "message": "…"],
                ["notification_id": "maison_request_rules", "title": "Maison", "message": "…"],
            ],
        ])
        let store = try await connected(transport)
        let connection = try #require(store.connection)

        #expect(await store.linkRequestedTrackers(through: connection))

        let updates = await transport.sentMessages(ofType: "person/update")
        #expect(updates.map { $0["person_id"]?.stringValue } == ["lea"])
        // Done: the request goes; the one that needs a choice stays.
        let dismissed = await transport.sentMessages(ofType: "call_service").filter { $0["service"]?.stringValue == "dismiss" }
        #expect(dismissed.map { $0["service_data"]?["notification_id"]?.stringValue } == [request.notificationID])
    }

    @Test func signingOutRemovesMaisonsDeviceFromTheServer() async throws {
        let http = ScriptedHTTPClient { _ in (200, #"{"require_restart": false}"#) }
        let webhooks = MemoryWebhookStorage(webhook)
        let store = try await connected(server(isAdmin: true), http: http, webhooks: webhooks)

        await store.signOut()

        #expect(http.sent.map(\.httpMethod) == ["DELETE"])
        #expect(http.sent.map { $0.url?.path() } == ["/api/config/config_entries/entry/entry-maison"])
        #expect(store.phase == .signedOut)
        #expect(webhooks.load() == nil)
    }

    @Test func aResidentSignsOutWithoutAnError() async throws {
        let http = ScriptedHTTPClient { _ in (401, "") }
        let webhooks = MemoryWebhookStorage(webhook)
        let store = try await connected(server(isAdmin: false), http: http, webhooks: webhooks)

        await store.signOut()

        #expect(http.sent.isEmpty)
        #expect(store.phase == .signedOut)
        #expect(webhooks.load() == nil)
    }
}
