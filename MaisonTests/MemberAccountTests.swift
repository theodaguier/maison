import CloudKit
import Foundation
@testable import Maison
import Testing

/// The account Maison makes for someone invited, from the invitation to their first sign-in.
struct MemberAccountTests {
    let server = URL(string: "http://192.168.1.179:8123")!
    let remote = URL(string: "https://maison.ui.nabu.casa")!

    // MARK: - Server commands

    @Test func createsAnAdministratorWithAPersonForPresence() async throws {
        let transport = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": [["type": "auth_ok", "ha_version": "2026.8.1"]]
            case "config/auth/create": [result(for: message, ["user": ["id": "u1"]])]
            default: [result(for: message)]
            }
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        let id = try await connection.createAdministrator(named: "Camille", username: "maison-ab12", password: "secret")

        #expect(id == "u1")
        let user = try #require(await transport.sentMessages(ofType: "config/auth/create").first)
        #expect(user["name"] == "Camille")
        #expect(user["group_ids"] == ["system-admin"])
        #expect(user["local_only"] == false)
        let login = try #require(await transport.sentMessages(ofType: "config/auth_provider/homeassistant/create").first)
        #expect(login["user_id"] == "u1")
        #expect(login["username"] == "maison-ab12")
        #expect(login["password"] == "secret")
        let person = try #require(await transport.sentMessages(ofType: "person/create").first)
        #expect(person["user_id"] == "u1")
    }

    @Test func deletingAnAccountDeletesItsPersonToo() async throws {
        let transport = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": [["type": "auth_ok", "ha_version": "2026.8.1"]]
            case "person/list": [result(for: message, ["storage": [["id": "camille", "user_id": "u1"], ["id": "theo", "user_id": "u0"]]])]
            default: [result(for: message)]
            }
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()

        try await connection.deleteAccount("u1")

        #expect(await transport.sentMessages(ofType: "person/delete").map { $0["person_id"] } == ["camille"])
        #expect(await transport.sentMessages(ofType: "config/auth/delete").map { $0["user_id"] } == ["u1"])
    }

    // MARK: - Signing in

    @Test func signsInThroughTheLoginFlow() async throws {
        let http = ScriptedHTTPClient { request in
            switch request.url?.path() {
            case "/auth/login_flow": (200, #"{"type":"form","flow_id":"f1","step_id":"init"}"#)
            case "/auth/login_flow/f1": (200, #"{"type":"create_entry","flow_id":"f1","result":"code1"}"#)
            default: (200, #"{"access_token":"access","expires_in":1800,"refresh_token":"refresh","token_type":"Bearer"}"#)
            }
        }

        let credentials = try await HomeAssistantAuth(serverURL: server, http: http)
            .signIn(username: "maison-ab12", password: "secret", now: Date(timeIntervalSince1970: 0))

        #expect(credentials.refreshToken == "refresh")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1800))
        #expect(http.sent.map { $0.url?.path() } == ["/auth/login_flow", "/auth/login_flow/f1", "/auth/token"])
        let start = try JSONDecoder().decode(JSONValue.self, from: try #require(http.sent[0].httpBody))
        #expect(start["handler"] == ["homeassistant", nil])
        #expect(start["client_id"] == "https://theodaguier.github.io/maison/")
        let step = try JSONDecoder().decode(JSONValue.self, from: try #require(http.sent[1].httpBody))
        #expect(step["username"] == "maison-ab12")
        #expect(step["password"] == "secret")
        let token = String(decoding: try #require(http.sent[2].httpBody), as: UTF8.self)
        #expect(token.contains("code=code1"))
    }

    @Test func aRefusedPasswordFailsTheSignIn() async {
        let http = ScriptedHTTPClient { request in
            request.url?.path() == "/auth/login_flow"
                ? (200, #"{"type":"form","flow_id":"f1","step_id":"init"}"#)
                : (200, #"{"type":"form","flow_id":"f1","step_id":"init","errors":{"base":"invalid_auth"}}"#)
        }

        await #expect(throws: HomeAssistantError.authenticationFailed("invalid_auth")) {
            try await HomeAssistantAuth(serverURL: server, http: http).signIn(username: "maison-ab12", password: "wrong")
        }
        #expect(http.sent.count == 2)
    }

    @Test func signsInThroughTheRemoteAddressAwayFromHome() async throws {
        let tried = Log<URL>()
        let connector = ServerConnector(signIn: { address, _, _ in
            tried.append(address)
            if address == server { throw URLError(.cannotConnectToHost) }
            return Credentials(serverURL: address, accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
        })

        let credentials = try await connector.signIn(username: "u", password: "p", addresses: [server, remote])

        #expect(credentials.serverURL == remote)
        #expect(tried.values == [server, remote])
    }

    @Test func aRefusedSignInIsNotRetriedElsewhere() async {
        let tried = Log<URL>()
        let connector = ServerConnector(signIn: { address, _, _ in
            tried.append(address)
            throw HomeAssistantError.authenticationFailed("invalid_auth")
        })

        await #expect(throws: HomeAssistantError.authenticationFailed("invalid_auth")) {
            try await connector.signIn(username: "u", password: "p", addresses: [server, remote])
        }
        #expect(tried.values == [server])
    }

    // MARK: - Record

    @Test func theRecordKeepsThePasswordEncrypted() {
        let zone = CKRecordZone.ID(zoneName: "Household", ownerName: CKCurrentUserDefaultName)
        let access = MemberAccess(participantID: "p1", accountID: "u1", username: "maison-ab12", password: "secret")

        let record = access.record(in: zone)

        #expect(record.recordID.recordName == "access-p1")
        #expect(record["password"] == nil)
        #expect(MemberAccess(record: record) == access)
    }

    @Test func madeUpCredentialsAreNeverTheSame() {
        #expect(MemberAccess.makeUsername() != MemberAccess.makeUsername())
        #expect(MemberAccess.makeUsername().hasPrefix("maison-"))
        #expect(MemberAccess.makePassword() != MemberAccess.makePassword())
        #expect(MemberAccess.makePassword().count >= 32)
    }
}

/// Inviting, removing and joining, through the household store and the in-memory iCloud.
@MainActor
struct MemberAccountHouseholdTests {
    let defaults = UserDefaults(suiteName: "MemberAccountHouseholdTests-\(UUID().uuidString)")!
    let server = Household(name: "Maison", serverURL: URL(string: "http://192.168.1.179:8123")!)

    @Test func invitingSomeoneMakesTheirAccountOnce() async throws {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)
        let made = Log<String>()

        let link = try await store.invite("camille@icloud.com") { name, username, _ in
            made.append(name)
            return "u-\(username)"
        }
        _ = try await store.invite("camille@icloud.com") { _, _, _ in
            made.append("again")
            return "other"
        }

        #expect(link.host() == "www.icloud.com")
        #expect(made.values == ["camille@icloud.com"])
        let access = try #require(await cloud.storedAccess(of: "camille@icloud.com", in: .owned))
        #expect(access.accountID == "u-\(access.username)")
        #expect(access.password != nil)
        #expect(store.members.last?.role == .administrator)
        #expect(store.members.last?.isPending == true)
    }

    @Test func anAccountThatCantBeMadeStopsTheInvitation() async throws {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)

        await #expect(throws: MemberAccountError.needsAdministrator) {
            try await store.invite("camille@icloud.com") { _, _, _ in throw MemberAccountError.needsAdministrator }
        }
        #expect(await cloud.storedAccess(of: "camille@icloud.com", in: .owned) == nil)
    }

    @Test func removingSomeoneDeletesTheirAccountFirst() async throws {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)
        _ = try await store.invite("camille@icloud.com") { _, _, _ in "u1" }
        let camille = try #require(store.members.first { $0.id == "camille@icloud.com" })

        await #expect(throws: HomeAssistantError.connectionClosed) {
            try await store.remove(camille) { _ in throw HomeAssistantError.connectionClosed }
        }
        #expect(store.members.contains { $0.id == camille.id })

        let deleted = Log<String>()
        try await store.remove(camille) { deleted.append($0) }

        #expect(deleted.values == ["u1"])
        #expect(!store.members.contains { $0.id == camille.id })
        #expect(await cloud.storedAccess(of: camille.id, in: .owned) == nil)
    }

    @Test func theInvitedPersonFindsTheirSignInUntilItIsUsed() async throws {
        let cloud = FakeHouseholdCloud()
        let location = await cloud.addSharedHousehold(server, members: [])
        await cloud.setCurrentParticipant("p1", in: location)
        try await cloud.saveMemberAccess(MemberAccess(participantID: "p1", accountID: "u1", username: "maison-ab12", password: "secret"), in: location)
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.start()

        let access = try #require(await store.unusedAccess())
        #expect(access.password == "secret")

        await store.accessUsed(access)

        #expect(await store.unusedAccess() == nil)
        #expect(await cloud.storedAccess(of: "p1", in: location)?.accountID == "u1")
    }

    @Test func joiningSignsInWithTheAccountMadeForThem() async throws {
        let cloud = FakeHouseholdCloud()
        let location = await cloud.addSharedHousehold(server, members: [])
        await cloud.setCurrentParticipant("p1", in: location)
        try await cloud.saveMemberAccess(MemberAccess(participantID: "p1", accountID: "u1", username: "maison-ab12", password: "secret"), in: location)
        let transport = fakeHomeServer()
        let signIns = Log<String>()
        let connector = ServerConnector(
            signIn: { address, username, password in
                signIns.append("\(username):\(password)")
                return Credentials(serverURL: address, accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
            },
            open: { _, token in HomeAssistantConnection(transport: transport, accessToken: token) }
        )
        let keychain = MemoryCredentialStorage()
        let store = HomeStore(
            credentialStore: keychain, defaults: defaults,
            household: HouseholdStore(cloud: cloud, defaults: defaults),
            presence: PresenceReporter(webhooks: MemoryWebhookStorage(), defaults: defaults),
            connector: connector
        )
        await store.household.start()

        await store.signInWithInvitation()

        #expect(signIns.values == ["maison-ab12:secret"])
        #expect(store.phase == .connected)
        #expect(try keychain.load()?.refreshToken == "r")
        let change = try #require(await transport.sentMessages(ofType: "config/auth_provider/homeassistant/change_password").first)
        #expect(change["current_password"] == "secret")
        #expect(change["new_password"] != "secret")
        #expect(await cloud.storedAccess(of: "p1", in: location)?.password == nil)
    }
}
