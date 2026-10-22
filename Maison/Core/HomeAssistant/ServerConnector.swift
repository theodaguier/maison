import Foundation

/// Opens a connection through the first of the server's addresses that answers: the local one at home,
/// the remote one away. Expired tokens are refreshed through that same address.
struct ServerConnector: Sendable {
    /// How long an address may take before the next one is tried. The last address gets the system's own timeout.
    var timeout: Duration = .seconds(3)
    var refresh: @Sendable (Credentials, URL) async throws -> Credentials = { credentials, address in
        try await HomeAssistantAuth(serverURL: address).refresh(credentials)
    }

    var open: @Sendable (URL, String) -> HomeAssistantConnection = { address, accessToken in
        HomeAssistantConnection(serverURL: address, accessToken: accessToken)
    }

    struct Opened: Sendable {
        let connection: HomeAssistantConnection
        /// Refreshed when the access token had expired.
        let credentials: Credentials
        let address: URL
    }

    func connect(_ credentials: Credentials, now: Date = .now) async throws -> Opened {
        var credentials = credentials
        var lastError: any Error = HomeAssistantError.connectionClosed
        let addresses = credentials.addresses
        for (index, address) in addresses.enumerated() {
            let limit = index == addresses.count - 1 ? nil : timeout
            do {
                if credentials.isExpired(at: now) {
                    let expired = credentials
                    credentials = try await Self.run(within: limit) { try await refresh(expired, address) }
                }
                let connection = open(address, credentials.accessToken)
                try await Self.run(within: limit, onTimeout: { await connection.disconnect() }) {
                    try await connection.connect()
                }
                return Opened(connection: connection, credentials: credentials, address: address)
            } catch HomeAssistantError.authenticationFailed(let message) {
                // Another address leads to the same server: it would refuse the sign-in too.
                throw HomeAssistantError.authenticationFailed(message)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Runs `operation`, giving up after `limit`. `onTimeout` must make the operation return.
    static func run<T: Sendable>(
        within limit: Duration?,
        onTimeout: @escaping @Sendable () async -> Void = {},
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let limit else { return try await operation() }
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                return nil
            }
            defer { group.cancelAll() }
            if let value = try await group.next() ?? nil {
                return value
            }
            await onTimeout()
            throw URLError(.timedOut)
        }
    }
}

extension ServerConfig {
    /// The address that works away from home: the external URL set in Home Assistant, otherwise
    /// Home Assistant Cloud's remote access when it is turned on. `cloudStatus` answers `cloud/status`.
    func remoteURL(cloudStatus: JSONValue?) -> URL? {
        if let externalURL, let url = URL(string: externalURL), url.host() != nil {
            return url
        }
        guard
            let cloudStatus, cloudStatus["logged_in"]?.boolValue == true,
            cloudStatus["prefs"]?["remote_enabled"]?.boolValue == true,
            let domain = cloudStatus["remote_domain"]?.stringValue, !domain.isEmpty
        else { return nil }
        return URL(string: "https://\(domain)")
    }
}
