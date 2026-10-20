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
        /// The connection dropped; cached states are still shown while the store retries.
        case offline(since: Date)
        case failed(String)
    }

    private(set) var phase: Phase
    private(set) var states: [String: EntityState] = [:]
    private(set) var layout = HomeLayout()
    private(set) var serverURL: URL?
    private(set) var serverVersion: String?
    private(set) var lastUpdate: Date?
    private(set) var favoriteIDs: [String]
    private(set) var currentUser: HomeAssistantUser?
    private(set) var serverConfig: ServerConfig?
    private(set) var integrations: [Integration] = []
    /// Recent round-trip times to the server, oldest first.
    private(set) var latencies: [Duration] = []
    let discovery = ServerDiscovery()

    @ObservationIgnored private let credentialStore: CredentialStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var credentials: Credentials?
    @ObservationIgnored private var connection: HomeAssistantConnection?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private let isDemo: Bool

    init(credentialStore: CredentialStore = CredentialStore(), defaults: UserDefaults = .standard) {
        self.credentialStore = credentialStore
        self.defaults = defaults
        favoriteIDs = defaults.stringArray(forKey: Self.favoritesKey) ?? []
        isDemo = false
        let credentials = try? credentialStore.load()
        self.credentials = credentials
        serverURL = credentials?.serverURL
        phase = credentials == nil ? .signedOut : .connecting
    }

    /// A store filled with sample data, for previews and the `-demo` launch argument.
    init(demo states: [EntityState], layout: HomeLayout, phase: Phase = .connected) {
        credentialStore = CredentialStore(service: "com.theodaguier.maison.demo")
        defaults = UserDefaults(suiteName: "demo") ?? .standard
        favoriteIDs = []
        isDemo = true
        self.states = Dictionary(states.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
        self.layout = layout
        self.phase = phase
        serverURL = URL(string: "http://homeassistant.local:8123")
        serverVersion = "2026.8.1"
        lastUpdate = .now
        currentUser = HomeAssistantUser(name: "Théo", isAdmin: true)
        serverConfig = ServerConfig(locationName: "Maison", version: "2026.8.1", externalURL: nil, internalURL: "http://homeassistant.local:8123")
        integrations = [
            Integration(domain: "sonos", title: "Sonos", state: "loaded"),
            Integration(domain: "hue", title: "Philips Hue", state: "loaded"),
            Integration(domain: "mobile_app", title: "iPhone", state: "loaded"),
        ]
        latencies = [34, 30, 41, 36, 52, 33, 31, 35].map { .milliseconds($0) }
    }

    private static let favoritesKey = "favoriteEntityIDs"

    // MARK: - Session

    func start() async {
        guard !isDemo else { return }
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
        guard !isDemo else { return }
        guard var credentials else {
            phase = .signedOut
            return
        }
        retryTask?.cancel()
        if states.isEmpty {
            phase = .connecting
        }
        do {
            if credentials.isExpired() {
                credentials = try await HomeAssistantAuth(serverURL: credentials.serverURL).refresh(credentials)
                try credentialStore.save(credentials)
                self.credentials = credentials
            }
            let connection = HomeAssistantConnection(serverURL: credentials.serverURL, accessToken: credentials.accessToken)
            try await connection.connect()
            async let states = connection.states()
            async let layout = connection.layout()
            let changes = try await connection.stateChanges()
            let (loadedStates, loadedLayout) = try await (states, layout)

            await self.connection?.disconnect()
            self.connection = connection
            self.states = Dictionary(loadedStates.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
            self.layout = loadedLayout
            serverVersion = await connection.serverVersion
            lastUpdate = .now
            phase = .connected
            Task { await loadServerDetails(from: connection) }

            updatesTask?.cancel()
            updatesTask = Task { [weak self] in
                for await state in changes {
                    self?.states[state.entityID] = state
                    self?.lastUpdate = .now
                }
                guard !Task.isCancelled else { return }
                self?.connectionLost()
            }
        } catch HomeAssistantError.authenticationFailed(let message) {
            phase = .failed(message ?? String(localized: "Home Assistant refused the sign-in."))
        } catch {
            if states.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                connectionLost()
            }
        }
    }

    private func connectionLost() {
        if case .offline = phase {} else {
            phase = .offline(since: lastUpdate ?? .now)
        }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    /// Details for the Settings tab; failures here never affect the connection.
    private func loadServerDetails(from connection: HomeAssistantConnection) async {
        currentUser = try? await connection.currentUser()
        serverConfig = try? await connection.serverConfig()
        integrations = (try? await connection.integrations()) ?? []
    }

    func measureLatency() async {
        guard let connection, let duration = try? await connection.ping() else { return }
        latencies = Array((latencies + [duration]).suffix(20))
    }

    func signOut() async {
        updatesTask?.cancel()
        retryTask?.cancel()
        updatesTask = nil
        await connection?.disconnect()
        connection = nil
        try? credentialStore.delete()
        credentials = nil
        serverURL = nil
        states = [:]
        layout = HomeLayout()
        phase = .signedOut
        discovery.start()
    }

    // MARK: - Actions

    func call(_ domain: String, _ service: String, on entity: EntityState, data: [String: JSONValue] = [:]) async {
        guard let connection else { return }
        do {
            try await connection.callService(domain: domain, service: service, entityID: entity.entityID, data: data)
        } catch HomeAssistantError.connectionClosed {
            connectionLost()
        } catch {
            // Rejected calls leave the state unchanged; the live update stream shows the truth.
        }
    }

    func performPrimaryAction(on entity: EntityState) async {
        guard let command = DeviceCommand(primaryActionFor: entity) else { return }
        await call(command.domain, command.service, on: entity)
    }

    func setLevel(_ level: Double, on entity: EntityState) async {
        let percent = Int((level * 100).rounded())
        switch entity.kind {
        case .light:
            if percent == 0 {
                await call("light", "turn_off", on: entity)
            } else {
                await call("light", "turn_on", on: entity, data: ["brightness_pct": .number(Double(percent))])
            }
        case .cover:
            await call("cover", "set_cover_position", on: entity, data: ["position": .number(Double(percent))])
        case .fan:
            await call("fan", "set_percentage", on: entity, data: ["percentage": .number(Double(percent))])
        default:
            break
        }
    }

    func setTargetTemperature(_ temperature: Double, on entity: EntityState) async {
        await call("climate", "set_temperature", on: entity, data: ["temperature": .number(temperature)])
    }

    func toggleFavorite(_ entity: EntityState) {
        if let index = favoriteIDs.firstIndex(of: entity.entityID) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(entity.entityID)
        }
        defaults.set(favoriteIDs, forKey: Self.favoritesKey)
    }

    func isFavorite(_ entity: EntityState) -> Bool {
        favoriteIDs.contains(entity.entityID)
    }
}

// MARK: - Derived data

extension HomeStore {
    /// Entities that belong in device lists: controllable or informative, not hidden in Home Assistant.
    var devices: [EntityState] {
        states.values.filter { entity in
            !layout.hiddenEntities.contains(entity.entityID)
                && ![.other, .scene, .script, .automation, .button].contains(entity.kind)
        }
    }

    func area(of entity: EntityState) -> Area? {
        guard let id = layout.areaByEntity[entity.entityID] else { return nil }
        return layout.areas.first { $0.id == id }
    }

    func devices(in area: Area) -> [EntityState] {
        devices.filter { layout.areaByEntity[$0.entityID] == area.id }.sortedByName()
    }

    /// Rooms that contain at least one device.
    var rooms: [Area] {
        let used = Set(devices.compactMap { layout.areaByEntity[$0.entityID] })
        return layout.areas.filter { used.contains($0.id) }
    }

    /// The user's favourites, or a sensible selection of controllable devices until they pick some.
    var favorites: [EntityState] {
        let chosen = favoriteIDs.compactMap { states[$0] }
        if !chosen.isEmpty { return chosen }
        // One device of each kind first, in this order, then a second round, up to six.
        let order: [DeviceKind] = [.light, .switch, .climate, .mediaPlayer, .lock, .cover, .fan]
        let byKind = Dictionary(grouping: devices.filter { order.contains($0.kind) && !$0.isUnavailable }, by: \.kind)
            .mapValues { $0.sortedByName() }
        var picked: [EntityState] = []
        var round = 0
        while picked.count < 6 {
            let next = order.compactMap { kind in byKind[kind].flatMap { round < $0.count ? $0[round] : nil } }
            if next.isEmpty { break }
            picked.append(contentsOf: next.prefix(6 - picked.count))
            round += 1
        }
        return picked
    }

    var scenes: [EntityState] {
        states.values
            .filter { ($0.kind == .scene || $0.kind == .script) && !layout.hiddenEntities.contains($0.entityID) }
            .sortedByName()
    }

    var automations: [EntityState] {
        states.values.filter { $0.kind == .automation }.sortedByName()
    }

    var lightsOn: [EntityState] {
        devices.filter { $0.kind == .light && $0.state == "on" }
    }

    /// The temperature shown in the hero ring, with where it comes from.
    var heroTemperature: HeroTemperature? {
        let indoorSensors = devices.filter {
            $0.kind == .sensor && $0.deviceClass == "temperature" && $0.numericState != nil
                && !$0.name.lowercased().contains("ext") && !$0.name.lowercased().contains("out")
        }
        if !indoorSensors.isEmpty {
            let values = indoorSensors.compactMap(\.numericState)
            return HeroTemperature(value: values.reduce(0, +) / Double(values.count), source: .indoor)
        }
        if let climate = devices.first(where: { $0.kind == .climate && $0.currentTemperature != nil }) {
            return HeroTemperature(value: climate.currentTemperature!, source: .indoor)
        }
        if let weather = states.values.first(where: { $0.domain == "weather" }),
           let value = weather.attributes["temperature"]?.doubleValue {
            return HeroTemperature(value: value, source: .outdoor)
        }
        return nil
    }

    /// Today's energy use, from the first energy sensor whose name says it is a daily total.
    var energyToday: EntityState? {
        devices.first {
            $0.kind == .sensor && $0.deviceClass == "energy" && $0.numericState != nil
                && ["today", "aujourd", "daily", "jour"].contains(where: $0.name.lowercased().contains)
        }
    }

    func averageValue(of deviceClass: String, in area: Area) -> Double? {
        let values = devices(in: area).filter { $0.kind == .sensor && $0.deviceClass == deviceClass }.compactMap(\.numericState)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The most recent motion in a room, if it has a motion sensor.
    func lastMotion(in area: Area) -> Date? {
        devices(in: area)
            .filter { $0.kind == .binarySensor && ["motion", "occupancy", "presence"].contains($0.deviceClass ?? "") }
            .compactMap { $0.isActive ? Date.now : $0.lastChanged }
            .max()
    }

    /// The short sentences of the home summary card.
    var summary: HomeSummary {
        var sentences: [String] = []
        let locks = devices.filter { $0.kind == .lock }
        let openings = devices.filter { $0.kind == .binarySensor && ["door", "window", "garage_door", "opening"].contains($0.deviceClass ?? "") && $0.isActive }
        let unlocked = locks.filter { $0.state == "unlocked" }

        if let lock = locks.first(where: { $0.state == "locked" }), unlocked.isEmpty {
            if let since = lock.lastChanged {
                sentences.append(String(localized: "\(lock.name) has been locked since \(since.formatted(date: .omitted, time: .shortened))."))
            } else {
                sentences.append(String(localized: "\(lock.name) is locked."))
            }
        }
        for lock in unlocked {
            sentences.append(String(localized: "\(lock.name) is unlocked."))
        }
        for opening in openings.prefix(2) {
            sentences.append(String(localized: "\(opening.name) is open."))
        }

        let lights = lightsOn
        if lights.isEmpty {
            sentences.append(String(localized: "All lights are off."))
        } else {
            let rooms = Set(lights.compactMap { area(of: $0)?.name })
            if rooms.count == 1, let room = rooms.first {
                sentences.append(String(localized: "\(lights.count) lights on, all in \(room)."))
            } else {
                sentences.append(String(localized: "\(lights.count) lights on."))
            }
        }

        let isCalm = unlocked.isEmpty && openings.isEmpty
        return HomeSummary(
            title: isCalm ? String(localized: "All Quiet at Home") : String(localized: "Worth a Look"),
            text: sentences.joined(separator: " "),
            isCalm: isCalm
        )
    }
}

struct HeroTemperature: Equatable {
    enum Source { case indoor, outdoor }
    let value: Double
    let source: Source
}

struct HomeSummary: Equatable {
    let title: String
    let text: String
    let isCalm: Bool
}

extension Sequence where Element == EntityState {
    func sortedByName() -> [EntityState] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
