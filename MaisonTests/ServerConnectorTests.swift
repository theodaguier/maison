import Foundation
import Testing
@testable import Maison

struct ServerConnectorTests {
    let local = URL(string: "http://homeassistant.local:8123")!
    let remote = URL(string: "https://maison.example.com")!

    func credentials(expiresAt: Date = .distantFuture) -> Credentials {
        Credentials(serverURL: local, accessToken: "access", refreshToken: "refresh", expiresAt: expiresAt, remoteURL: remote)
    }

    @Test func listsTheLocalAddressFirstWithoutDuplicates() {
        #expect(credentials().addresses == [local, remote])
        var signedInRemotely = credentials()
        signedInRemotely.remoteURL = local
        #expect(signedInRemotely.addresses == [local])
    }

    @Test func usesTheLocalAddressWhenItAnswers() async throws {
        let opened = Log<URL>()
        let connector = ServerConnector(open: { address, token in
            opened.append(address)
            return HomeAssistantConnection(transport: FakeTransport(), accessToken: token)
        })

        let result = try await connector.connect(credentials())

        #expect(result.address == local)
        #expect(opened.values == [local])
    }

    @Test func switchesToTheRemoteAddressAwayFromHome() async throws {
        let connector = ServerConnector(open: { address, token in
            HomeAssistantConnection(transport: address == local ? FailingTransport() : FakeTransport(), accessToken: token)
        })

        let result = try await connector.connect(credentials())

        #expect(result.address == remote)
        #expect(await result.connection.serverVersion == "2026.8.1")
    }

    @Test func givesUpOnALocalAddressThatNeverAnswers() async throws {
        let connector = ServerConnector(timeout: .milliseconds(50), open: { address, token in
            HomeAssistantConnection(transport: address == local ? SilentTransport() : FakeTransport(), accessToken: token)
        })

        let result = try await connector.connect(credentials())

        #expect(result.address == remote)
    }

    @Test func refreshesAnExpiredTokenThroughTheAddressThatAnswers() async throws {
        let refreshedAt = Log<URL>()
        let connector = ServerConnector(
            refresh: { credentials, address in
                refreshedAt.append(address)
                guard address == remote else { throw URLError(.cannotFindHost) }
                var refreshed = credentials
                refreshed.accessToken = "new"
                refreshed.expiresAt = .distantFuture
                return refreshed
            },
            open: { _, token in
                let transport = FakeTransport { message in
                    guard message["type"]?.stringValue == "auth" else { return [] }
                    return message["access_token"]?.stringValue == "new"
                        ? [["type": "auth_ok", "ha_version": "2026.8.1"]]
                        : [["type": "auth_invalid", "message": "Expired"]]
                }
                return HomeAssistantConnection(transport: transport, accessToken: token)
            }
        )

        let result = try await connector.connect(credentials(expiresAt: .distantPast))

        #expect(refreshedAt.values == [local, remote])
        #expect(result.address == remote)
        #expect(result.credentials.accessToken == "new")
        #expect(result.credentials.refreshToken == "refresh")
    }

    @Test func doesNotTryAnotherAddressWhenTheSignInIsRefused() async {
        let opened = Log<URL>()
        let connector = ServerConnector(open: { address, token in
            opened.append(address)
            let transport = FakeTransport { message in
                message["type"]?.stringValue == "auth" ? [["type": "auth_invalid", "message": "Revoked"]] : []
            }
            return HomeAssistantConnection(transport: transport, accessToken: token)
        })

        await #expect(throws: HomeAssistantError.authenticationFailed("Revoked")) {
            try await connector.connect(credentials())
        }
        #expect(opened.values == [local])
    }

    // MARK: - Remote address

    @Test func prefersTheExternalURL() {
        let config = ServerConfig(locationName: nil, version: nil, externalURL: "https://maison.example.com", internalURL: nil)
        #expect(config.remoteURL(cloudStatus: Self.cloud(remoteEnabled: true)) == remote)
    }

    @Test func fallsBackOnHomeAssistantCloud() {
        let config = ServerConfig(locationName: nil, version: nil, externalURL: "", internalURL: nil)
        #expect(config.remoteURL(cloudStatus: Self.cloud(remoteEnabled: true)) == URL(string: "https://abc123.ui.nabu.casa"))
        #expect(config.remoteURL(cloudStatus: Self.cloud(remoteEnabled: false)) == nil)
        #expect(config.remoteURL(cloudStatus: nil) == nil)
    }

    static func cloud(remoteEnabled: Bool) -> JSONValue {
        ["logged_in": true, "remote_domain": "abc123.ui.nabu.casa", "prefs": ["remote_enabled": .bool(remoteEnabled)]]
    }
}

/// A server that can't be reached: the connection fails at once.
struct FailingTransport: WebSocketTransport {
    func send(_ text: String) async throws { throw URLError(.cannotConnectToHost) }
    func receive() async throws -> String { throw URLError(.cannotConnectToHost) }
    func close() {}
}

/// A server that never answers, until the connection is closed.
actor SilentTransport: WebSocketTransport {
    private var waiters: [CheckedContinuation<String, any Error>] = []
    private var isClosed = false

    func send(_ text: String) async throws {}

    func receive() async throws -> String {
        if isClosed { throw URLError(.cancelled) }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    nonisolated func close() {
        Task { await closeNow() }
    }

    private func closeNow() {
        isClosed = true
        waiters.forEach { $0.resume(throwing: URLError(.cancelled)) }
        waiters.removeAll()
    }
}

/// Thread-safe list for recording calls from `@Sendable` closures.
final class Log<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] { lock.withLock { storage } }

    func append(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}
