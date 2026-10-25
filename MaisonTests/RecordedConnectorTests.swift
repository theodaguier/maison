import Foundation
@testable import Maison
import Testing

/// Recorded Home Assistant replies, played back offline.
///
/// WebSocket commands go through `FakeTransport` with the JSON the connection decodes.
/// REST goes through `FixtureURLProtocol`, so `URLSession` never opens a socket.
/// There is no box or router connector in this tree: the router shows up as Home Assistant
/// entities, and those entities are in the recorded state list.
struct RecordedWebSocketTests {
    @Test func parsesTheRecordedStates() async throws {
        let connection = try await recordedConnection(results: ["get_states": "states"])
        #expect(await connection.serverVersion == "2026.8.1")

        let states = try await connection.states()

        #expect(states.map(\.entityID) == ["light.salon", "sensor.salon_temperature", "climate.salon", "lock.porte"])
        #expect(states.map(\.kind) == [.light, .sensor, .climate, .lock])
        #expect(states[0].name == "Salon")
        #expect(states[0].attributes["brightness"]?.intValue == 180)
        let changed = try #require(EntityState.parseDate("2026-10-20T08:12:03.123456+00:00"))
        #expect(states[0].lastChanged == changed)
        #expect(states[1].name == "Température salon")
        #expect(states[1].deviceClass == "temperature")
        #expect(states[1].numericState == 21.5)
        #expect(states[2].currentTemperature == 21.0)
        #expect(states[2].attributes["temperature"]?.doubleValue == 20.0)
        #expect(states[3].state == "locked")
    }

    @Test func parsesRegistriesAndTheMobileAppTracker() async throws {
        let connection = try await recordedConnection(results: [
            "config/area_registry/list": "areas",
            "config/entity_registry/list": "entities",
            "config/device_registry/list": "devices",
        ])

        let layout = try await connection.layout()
        #expect(layout.areas.map(\.name) == ["Entrée", "Salon"])
        #expect(layout.areaByEntity["light.salon"] == "salon")
        #expect(layout.areaByEntity["binary_sensor.porte"] == "entree")
        #expect(layout.deviceByEntity["light.salon"] == "dev-bulb")
        #expect(layout.platformByEntity["light.salon"] == "hue")
        #expect(layout.hiddenEntities == Set(["sensor.salon_battery", "sensor.disabled"]))

        let entities = try await connection.send(["type": "config/entity_registry/list"])
        let tracker = entities.arrayValue?.first {
            $0["platform"]?.stringValue == "mobile_app" && $0["unique_id"]?.stringValue == "wh-from-ha"
                && $0["entity_id"]?.stringValue?.hasPrefix("device_tracker.") == true
        }
        #expect(tracker?["entity_id"]?.stringValue == "device_tracker.iphone")
    }

    @Test func readsHistoryLogbookAndStatistics() async throws {
        let connection = try await recordedConnection(results: [
            "history/history_during_period": "history",
            "logbook/get_events": "logbook",
            "recorder/statistics_during_period": "statistics",
        ])
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let history = try await connection.history(of: "light.salon", since: start)
        #expect(history.map(\.state) == ["off", "on"])
        #expect(history.map(\.date) == [
            Date(timeIntervalSince1970: 1_760_000_000),
            Date(timeIntervalSince1970: 1_760_003_600),
        ])

        let logbook = try await connection.logbook(of: "light.salon", since: start)
        #expect(logbook.map(\.state) == ["on", "off", "on"])
        #expect(logbook.map(\.userID) == ["user-1", nil, nil])
        #expect(logbook.map(\.automationName) == [nil, "Dernier départ", "Soir"])

        let statistics = try await connection.statistics(of: "sensor.salon_temperature", since: start, period: "hour")
        #expect(statistics.map(\.start) == [
            Date(timeIntervalSince1970: 1_760_000_000),
            Date(timeIntervalSince1970: 1_760_003_600),
        ])
        #expect(statistics.map(\.mean) == [21.5, 19.0] as [Double?])
        #expect(statistics.map(\.min) == [20.1, 18.2] as [Double?])
        #expect(statistics.map(\.max) == [22.4, 19.8] as [Double?])
    }

    @Test func readsTheGridMetersOfTheEnergyDashboard() async throws {
        let connection = try await recordedConnection(results: ["energy/get_prefs": "energy-prefs"])
        // Solar production and per-device meters are not electricity taken from the grid.
        #expect(try await connection.gridConsumptionStatistics() == ["sensor.linky_hchc", "sensor.linky_hchp"])
    }

    @Test func readsTheUserConfigIntegrationsAndCloudAddress() async throws {
        let connection = try await recordedConnection(results: [
            "auth/current_user": "current-user",
            "get_config": "config",
            "config_entries/get": "integrations",
            "cloud/status": "cloud-status",
        ])

        let user = try await connection.currentUser()
        #expect(user == HomeAssistantUser(id: "abc123", name: "Théo", isAdmin: true))

        let config = try await connection.serverConfig()
        #expect(config.locationName == "Maison")
        #expect(config.version == "2026.8.1")
        #expect(config.country == "FR")
        #expect(config.internalURL == "http://homeassistant.local:8123")
        let cloud = try await connection.send(["type": "cloud/status"])
        #expect(config.remoteURL(cloudStatus: cloud) == URL(string: "https://maison.example.com"))

        let integrations = try await connection.integrations()
        #expect(integrations.map(\.domain) == ["hue", "sonos"])
        #expect(integrations.map(\.title) == ["Philips Hue", "Sonos"])
        #expect(integrations.map(\.state) == ["loaded", "setup_error"])
        #expect(integrations.map(\.entryID) == ["hue-1", "sonos-1"])
        #expect(integrations.map(\.isFailing) == [false, true])
    }

    @Test func cloudIsTheRemoteAddressWhenNoExternalURLIsSet() async throws {
        let connection = try await recordedConnection(results: [
            "get_config": "config-no-external",
            "cloud/status": "cloud-status",
        ])
        let disabled = try await recordedConnection(results: [
            "get_config": "config-no-external",
            "cloud/status": "cloud-status-disabled",
        ])

        let config = try await connection.serverConfig()
        let cloud = try await connection.send(["type": "cloud/status"])
        #expect(config.externalURL == nil)
        #expect(config.remoteURL(cloudStatus: cloud) == URL(string: "https://abc123.ui.nabu.casa"))

        let off = try await disabled.send(["type": "cloud/status"])
        #expect(try await disabled.serverConfig().remoteURL(cloudStatus: off) == nil)
    }

    @Test func readsAndUpdatesTheRecordedEntities() async throws {
        let connection = try await recordedConnection(events: ["subscribe_entities": "subscribe-entities-events"])

        let (initial, updates) = try await connection.entities()
        var states = initial
        #expect(states.keys.sorted() == ["light.salon", "sensor.salon_puissance"])
        #expect(states["light.salon"]?.name == "Salon")
        #expect(states["light.salon"]?.attributes["brightness"]?.intValue == 180)
        #expect(states["light.salon"]?.lastChanged == Date(timeIntervalSince1970: 1_792_483_923.123456))
        #expect(states["sensor.salon_puissance"]?.numericState == 412)

        var iterator = updates.makeAsyncIterator()
        let off = try #require(await iterator.next())
        #expect(off.apply(to: &states))
        #expect(states["light.salon"]?.state == "off")
        #expect(states["light.salon"]?.attributes["brightness"] == .null)
        #expect(states["light.salon"]?.attributes["friendly_name"] == "Salon")
        #expect(states["light.salon"]?.lastChanged == Date(timeIntervalSince1970: 1_792_483_980))

        // The sensor reported the same value: nothing to redraw.
        let sameValue = try #require(await iterator.next())
        #expect(!sameValue.apply(to: &states))

        let removedAttribute = try #require(await iterator.next())
        #expect(removedAttribute.apply(to: &states))
        #expect(states["light.salon"]?.attributes["brightness"] == nil)
        #expect(states["light.salon"]?.attributes["color_mode"] == "brightness")

        let removedEntity = try #require(await iterator.next())
        #expect(removedEntity.apply(to: &states))
        #expect(states.keys.sorted() == ["light.salon"])
    }

    @Test func rejectsTheRecordedAuthFailure() async throws {
        let greeting = try RecordedFixture.json("auth-required")
        let invalid = try RecordedFixture.json("auth-invalid")
        let transport = FakeTransport(responder: { message in
            message["type"]?.stringValue == "auth" ? [invalid] : []
        }, greeting: greeting)
        let connection = HomeAssistantConnection(transport: transport, accessToken: "expired")

        await #expect(throws: HomeAssistantError.authenticationFailed("Invalid access token or password")) {
            try await connection.connect()
        }
    }

    @Test func surfacesTheRecordedCommandError() async throws {
        let greeting = try RecordedFixture.json("auth-required")
        let authOK = try RecordedFixture.json("auth-ok")
        let error = try RecordedFixture.json("command-error")
        let transport = FakeTransport(responder: { message in
            guard message["type"]?.stringValue != "auth" else { return [authOK] }
            return [["id": message["id"] ?? .null, "type": "result", "success": false, "error": error]]
        }, greeting: greeting)
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        await #expect(throws: HomeAssistantError.commandFailed(code: "not_found", message: "Service not found.")) {
            try await connection.callService(domain: "light", service: "explode", entityID: "light.salon")
        }
    }

    @Test func listsRunsAndAutomationsThatUseAnEntity() async throws {
        let connection = try await recordedConnection(results: [
            "trace/list": "traces",
            "search/related": "search-related",
        ])

        let runs = try await connection.automationRuns()
        #expect(runs.map(\.automationID) == ["trop_chaud", "porte", "erreur"])
        #expect(runs.map(\.didRun) == [true, false, true])
        #expect(runs.map(\.failed) == [false, false, true])
        let started = try #require(EntityState.parseDate("2026-10-20T18:00:00.123456+00:00"))
        #expect(runs[0].start == started)

        let automations = try await connection.automations(using: "sensor.salon_temperature")
        #expect(automations == ["automation.trop_chaud", "automation.depart"])
    }

    @Test func readsNotifyServicesAndThePersonList() async throws {
        let connection = try await recordedConnection(results: [
            "get_services": "services",
            "person/list": "person-list",
        ])

        let services = try await connection.send(["type": "get_services"])
        #expect(services["notify"]?.objectValue.map { Array($0.keys).sorted() } == ["mobile_app_iphone_de_theo", "notify"])

        let persons = try await connection.send(["type": "person/list"])
        let person = persons["storage"]?.arrayValue?.first { $0["user_id"]?.stringValue == "abc123" }
        #expect(person?["id"]?.stringValue == "person-1")
        #expect(person?["device_trackers"]?.arrayValue?.compactMap(\.stringValue) == ["device_tracker.phone"])
    }

    @Test func aMalformedFrameFailsTheConnection() async throws {
        let greeting = String(decoding: try RecordedFixture.data("auth-required", directory: "Fixtures/HomeAssistant"), as: UTF8.self)
        let connection = HomeAssistantConnection(transport: ScriptedTextTransport([greeting, "{"]), accessToken: "token")

        await #expect(throws: DecodingError.self) {
            try await connection.connect()
        }
    }
}

/// REST clients (`HomeAssistantAuth`, `ConfigEditor`) against `FixtureURLProtocol`.
@Suite(.serialized)
struct RecordedRESTTests {
    let server = URL(string: "http://homeassistant.local:8123")!
    let remote = URL(string: "https://maison.example.com")!
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func exchangesACodeForTheRecordedTokens() async throws {
        let requests = Log<URLRequest>()
        let serverURL = server
        let moment = now
        let credentials = try await playOffline({ request in
            requests.append(request)
            return try .json(named: "token")
        }) { http in
            try await HomeAssistantAuth(serverURL: serverURL, http: http).exchange(code: "xyz", now: moment)
        }

        #expect(credentials == Credentials(
            serverURL: serverURL, accessToken: "access-token", refreshToken: "refresh-token",
            expiresAt: moment.addingTimeInterval(1_800)
        ))
        let sent = try #require(requests.values.first)
        #expect(sent.url?.path() == "/auth/token")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: sent.fixtureBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=xyz"))
    }

    @Test func refreshesATokenFromTheRecordedResponse() async throws {
        let requests = Log<URLRequest>()
        let serverURL = server
        let remoteURL = remote
        let moment = now
        let old = Credentials(
            serverURL: serverURL, accessToken: "old", refreshToken: "refresh-token",
            expiresAt: .distantPast, remoteURL: remoteURL
        )
        let refreshed = try await playOffline({ request in
            requests.append(request)
            return try .json(named: "token-refresh")
        }) { http in
            try await HomeAssistantAuth(serverURL: serverURL, http: http).refresh(old, now: moment)
        }

        #expect(refreshed.accessToken == "refreshed-access")
        #expect(refreshed.refreshToken == "refresh-token")
        #expect(refreshed.remoteURL == remoteURL)
        #expect(refreshed.expiresAt == moment.addingTimeInterval(1_800))
        let body = String(decoding: requests.values.first?.fixtureBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=refresh-token"))
    }

    @Test func reportsARevokedRefreshToken() async throws {
        let data = try RecordedFixture.data("token-invalid-grant", directory: "Fixtures/HomeAssistant")
        let serverURL = server
        let old = Credentials(serverURL: serverURL, accessToken: "old", refreshToken: "revoked", expiresAt: .distantPast)
        let message = String(decoding: data, as: UTF8.self)

        await #expect(throws: HomeAssistantError.authenticationFailed(message)) {
            try await playOffline({ _ in FixtureHTTPResponse(status: 400, body: data, failure: nil) }) { http in
                try await HomeAssistantAuth(serverURL: serverURL, http: http).refresh(old)
            }
        }
    }

    @Test func aTokenEndpointErrorIsNotASuccessfulRefresh() async throws {
        let serverURL = server
        let old = Credentials(serverURL: serverURL, accessToken: "old", refreshToken: "refresh-token", expiresAt: .distantPast)

        await #expect(throws: HomeAssistantError.invalidResponse(statusCode: 500)) {
            try await playOffline({ _ in FixtureHTTPResponse(status: 500, body: Data("unavailable".utf8), failure: nil) }) { http in
                try await HomeAssistantAuth(serverURL: serverURL, http: http).refresh(old)
            }
        }
    }

    @Test func aMalformedTokenResponseFailsToDecode() async throws {
        let serverURL = server
        let old = Credentials(serverURL: serverURL, accessToken: "old", refreshToken: "refresh-token", expiresAt: .distantPast)

        await #expect(throws: DecodingError.self) {
            try await playOffline({ _ in FixtureHTTPResponse(status: 200, body: Data("{".utf8), failure: nil) }) { http in
                try await HomeAssistantAuth(serverURL: serverURL, http: http).refresh(old)
            }
        }
    }

    @Test func aTimedOutTokenRequestThrows() async throws {
        let serverURL = server
        let old = Credentials(serverURL: serverURL, accessToken: "old", refreshToken: "refresh-token", expiresAt: .distantPast)
        do {
            _ = try await playOffline({ _ in .timedOut }) { http in
                try await HomeAssistantAuth(serverURL: serverURL, http: http).refresh(old)
            }
            Issue.record("Expected the refresh to time out")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record(Comment(rawValue: "Unexpected error: \(error)"))
        }
    }

    @Test func connectorRefreshesThroughTheAddressThatAnswers() async throws {
        let hosts = Log<String>()
        let moment = now
        let http = FixtureURLProtocol.client { request in
            hosts.append(request.url?.host() ?? "")
            if request.url?.host() == "homeassistant.local" { return .timedOut }
            return try .json(named: "token-refresh")
        }
        defer { FixtureURLProtocol.reset() }
        let connector = ServerConnector(
            refresh: { credentials, address in
                try await HomeAssistantAuth(serverURL: address, http: http).refresh(credentials, now: moment)
            },
            open: { _, token in
                let transport = FakeTransport { message in
                    guard message["type"]?.stringValue == "auth" else { return [] }
                    return message["access_token"]?.stringValue == "refreshed-access"
                        ? [["type": "auth_ok", "ha_version": "2026.8.1"]]
                        : [["type": "auth_invalid", "message": "Expired"]]
                }
                return HomeAssistantConnection(transport: transport, accessToken: token)
            }
        )
        let expired = Credentials(
            serverURL: server, accessToken: "old", refreshToken: "refresh-token",
            expiresAt: .distantPast, remoteURL: remote
        )

        let opened = try await connector.connect(expired)

        #expect(hosts.values == ["homeassistant.local", "maison.example.com"])
        #expect(opened.address == remote)
        #expect(opened.credentials.accessToken == "refreshed-access")
        #expect(opened.credentials.refreshToken == "refresh-token")
        #expect(await opened.connection.serverVersion == "2026.8.1")
    }

    @Test func connectorGivesUpWhenEveryTokenEndpointTimesOut() async throws {
        let http = FixtureURLProtocol.client { _ in .timedOut }
        defer { FixtureURLProtocol.reset() }
        let connector = ServerConnector(
            refresh: { credentials, address in
                try await HomeAssistantAuth(serverURL: address, http: http).refresh(credentials)
            },
            open: { _, token in HomeAssistantConnection(transport: FakeTransport(), accessToken: token) }
        )
        let expired = Credentials(serverURL: server, accessToken: "old", refreshToken: "refresh-token", expiresAt: .distantPast)

        do {
            _ = try await connector.connect(expired)
            Issue.record("Expected the refresh to time out")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record(Comment(rawValue: "Unexpected error: \(error)"))
        }
    }

    @Test func loadsARecordedAutomationAndItsLegacyShape() async throws {
        let serverURL = server
        try await playOffline { request in
            guard request.httpMethod == "GET" else { return FixtureHTTPResponse(status: 405, body: Data(), failure: nil) }
            let name = request.url?.path().hasSuffix("/soir") == true ? "automation-config-legacy" : "automation-config"
            return try .json(named: name)
        } body: { http in
            let editor = ConfigEditor(serverURL: serverURL, accessToken: "token", client: http)
            let current = try #require(try await editor.load(.automation, id: "trop_chaud"))
            let rule = AutomationRule(id: "trop_chaud", config: current)
            #expect(rule.name == "Trop chaud")
            #expect(rule.description == "Baisse le chauffage")
            #expect(rule.triggers == [.threshold(entityID: "sensor.salon_temperature", above: 26, below: nil)])
            #expect(rule.conditions == [.someoneHome])
            #expect(rule.actions == [.device(entityID: "climate.salon", service: "climate.set_temperature", data: ["temperature": 22])])
            #expect(rule.extra["mode"]?.stringValue == "single")

            let legacy = try #require(try await editor.load(.automation, id: "soir"))
            let old = AutomationRule(id: "soir", config: legacy)
            #expect(old.triggers == [.state(entityID: "binary_sensor.porte", to: "on", forMinutes: 30)])
            #expect(old.conditions == [.afterSunset])
            #expect(old.actions == [
                .device(entityID: "light.salon", service: "light.turn_off", data: [:]),
                .wait(minutes: 5),
            ])
            #expect(old.extra["mode"]?.stringValue == "restart")
        }
    }

    @Test func configEditorReportsMissingBrokenAndTimedOutDocuments() async throws {
        let serverURL = server
        try await playOffline { request in
            let path = request.url?.path() ?? ""
            if path.hasSuffix("/missing") { return FixtureHTTPResponse(status: 404, body: Data("{}".utf8), failure: nil) }
            if path.hasSuffix("/slow") { return .timedOut }
            return FixtureHTTPResponse(status: 500, body: Data("no".utf8), failure: nil)
        } body: { http in
            let editor = ConfigEditor(serverURL: serverURL, accessToken: "token", client: http)
            #expect(try await editor.load(.automation, id: "missing") == nil)
            await #expect(throws: HomeAssistantError.invalidResponse(statusCode: 500)) {
                try await editor.load(.automation, id: "broken")
            }
            do {
                _ = try await editor.load(.automation, id: "slow")
                Issue.record("Expected the load to time out")
            } catch let error as URLError {
                #expect(error.code == .timedOut)
            } catch {
                Issue.record(Comment(rawValue: "Unexpected error: \(error)"))
            }
            try await editor.delete(.automation, id: "missing")
            await #expect(throws: HomeAssistantError.invalidResponse(statusCode: 500)) {
                try await editor.delete(.automation, id: "broken")
            }
        }
    }

    @Test func savingAConfigSendsTheRecordedDocument() async throws {
        let requests = Log<URLRequest>()
        let serverURL = server
        try await playOffline { request in
            requests.append(request)
            return FixtureHTTPResponse(status: 200, body: Data(), failure: nil)
        } body: { http in
            let editor = ConfigEditor(serverURL: serverURL, accessToken: "token", client: http)
            try await editor.save(.script, id: "maison_soir", config: ["alias": "Soir"])
        }

        let sent = try #require(requests.values.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(sent.url?.path() == "/api/config/script/config/maison_soir")
        #expect(String(decoding: sent.fixtureBody ?? Data(), as: UTF8.self).contains("Soir"))
    }

    /// The reply `HomeStore.registerMobileApp` reads, through the same `MobileAppRegistration`.
    @Test func mobileAppRegistrationCarriesTheWebhook() throws {
        let reply = try RecordedFixture.json("mobile-app-registration")
        let registration = try #require(MobileAppRegistration(reply))
        let webhook = Webhook(
            id: registration.webhookID,
            localURL: server,
            remoteURL: registration.remoteURL,
            cloudhookURL: registration.cloudhookURL
        )

        #expect(webhook.id == "wh-from-ha")
        #expect(webhook.remoteURL == URL(string: "https://abc123.ui.nabu.casa"))
        #expect(webhook.cloudhookURL == URL(string: "https://hooks.nabu.casa/wh-from-ha"))
        #expect(webhook.endpoints(addresses: nil).map(\.absoluteString) == [
            "http://homeassistant.local:8123/api/webhook/wh-from-ha",
            "https://abc123.ui.nabu.casa/api/webhook/wh-from-ha",
            "https://hooks.nabu.casa/wh-from-ha",
        ])
        #expect(MobileAppRegistration(["remote_ui_url": "https://abc123.ui.nabu.casa"]) == nil)
    }
}

/// Installs the URL protocol stub for one call, then removes it.
private func playOffline<T: Sendable>(
    _ handler: @escaping FixtureURLProtocol.Handler,
    body: @Sendable (any HTTPClient) async throws -> T
) async throws -> T {
    defer { FixtureURLProtocol.reset() }
    return try await body(FixtureURLProtocol.client(serving: handler))
}

/// WebSocket that replays exact text frames, including ones that are not JSON.
private final class ScriptedTextTransport: WebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [String]

    init(_ frames: [String]) {
        self.frames = frames
    }

    func send(_ text: String) async throws {}

    func receive() async throws -> String {
        try lock.withLock {
            guard !frames.isEmpty else { throw URLError(.networkConnectionLost) }
            return frames.removeFirst()
        }
    }

    func close() {}
}
