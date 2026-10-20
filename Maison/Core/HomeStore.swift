import AuthenticationServices
import Foundation
import Observation

/// App-wide state: the signed-in server, its live connection and the current entity states.
@MainActor
@Observable
final class HomeStore {
    enum Phase: Equatable {
        case signedOut
        case connecting
        case connected
        case failed(String)
    }

    private(set) var phase: Phase
    private(set) var states: [String: EntityState] = [:]
    private(set) var serverURL: URL?
    let discovery = ServerDiscovery()

    @ObservationIgnored private let credentialStore: CredentialStore
    @ObservationIgnored private var credentials: Credentials?
    @ObservationIgnored private var connection: HomeAssistantConnection?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(credentialStore: CredentialStore = CredentialStore()) {
        self.credentialStore = credentialStore
        let credentials = try? credentialStore.load()
        self.credentials = credentials
        serverURL = credentials?.serverURL
        phase = credentials == nil ? .signedOut : .connecting
    }

    /// Devices worth showing, grouped by kind in display order.
    var devicesByKind: [(kind: DeviceKind, devices: [EntityState])] {
        let visible = states.values.filter { $0.kind != .other }
        let grouped = Dictionary(grouping: visible, by: \.kind)
        return DeviceKind.allCases.compactMap { kind in
            guard let devices = grouped[kind], !devices.isEmpty else { return nil }
            return (kind, devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    // MARK: - Session

    func start() async {
        if credentials == nil {
            discovery.start()
        } else {
            await connect()
        }
    }

    /// Runs Home Assistant's sign-in page through `authenticate`, which presents the URL and
    /// returns the callback URL (typically `WebAuthenticationSession.authenticate`).
    func signIn(to server: URL, authenticate: (URL) async throws -> URL) async {
        let auth = HomeAssistantAuth(serverURL: server)
        let state = UUID().uuidString
        do {
            let callbackURL = try await authenticate(auth.authorizationURL(state: state))
            let code = try HomeAssistantAuth.authorizationCode(from: callbackURL, expectedState: state)
            let credentials = try await auth.exchange(code: code)
            try credentialStore.save(credentials)
            self.credentials = credentials
            serverURL = server
            discovery.stop()
            await connect()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func connect() async {
        guard var credentials else {
            phase = .signedOut
            return
        }
        phase = .connecting
        do {
            if credentials.isExpired() {
                credentials = try await HomeAssistantAuth(serverURL: credentials.serverURL).refresh(credentials)
                try credentialStore.save(credentials)
                self.credentials = credentials
            }
            let connection = HomeAssistantConnection(serverURL: credentials.serverURL, accessToken: credentials.accessToken)
            try await connection.connect()
            let states = try await connection.states()
            let changes = try await connection.stateChanges()

            await self.connection?.disconnect()
            self.connection = connection
            self.states = Dictionary(states.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
            phase = .connected

            updatesTask?.cancel()
            updatesTask = Task { [weak self] in
                for await state in changes {
                    self?.states[state.entityID] = state
                }
                if !Task.isCancelled {
                    self?.phase = .failed(String(localized: "The connection to Home Assistant was lost."))
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        updatesTask?.cancel()
        updatesTask = nil
        await connection?.disconnect()
        connection = nil
        try? credentialStore.delete()
        credentials = nil
        serverURL = nil
        states = [:]
        phase = .signedOut
        discovery.start()
    }

    // MARK: - Actions

    func performPrimaryAction(on entity: EntityState) async {
        guard let connection, let command = DeviceCommand(primaryActionFor: entity) else { return }
        do {
            try await connection.callService(domain: command.domain, service: command.service, entityID: entity.entityID)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
