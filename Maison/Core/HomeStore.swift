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
    /// Counts service calls the server rejected or couldn't take, so the interface can signal them.
    private(set) var failedCommands = 0
    private(set) var states: [String: EntityState] = [:]
    private(set) var layout = HomeLayout()
    private(set) var serverURL: URL?
    private(set) var serverVersion: String?
    private(set) var lastUpdate: Date?
    private(set) var currentUser: HomeAssistantUser?
    private(set) var serverConfig: ServerConfig?
    private(set) var integrations: [Integration] = []
    /// Names of the NFC tags, by id, once `tags()` has listed them.
    private(set) var tagNames: [String: String] = [:]
    /// Recent round-trip times to the server, oldest first.
    private(set) var latencies: [Duration] = []
    let discovery = ServerDiscovery()
    /// The household shared through iCloud, which also keeps the favourites.
    let household: HouseholdStore

    @ObservationIgnored private let credentialStore: CredentialStore
    @ObservationIgnored private var credentials: Credentials?
    @ObservationIgnored private var connection: HomeAssistantConnection?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private let isDemo: Bool
    /// The sample home, opened from onboarding or with `-demo`.
    var isDemoHome: Bool { isDemo }

    init(credentialStore: CredentialStore = CredentialStore(), defaults: UserDefaults = .standard, household: HouseholdStore? = nil) {
        self.credentialStore = credentialStore
        self.household = household ?? HouseholdStore(cloud: CloudKitHousehold.isEntitled ? CloudKitHousehold() : nil, defaults: defaults)
        isDemo = false
        let credentials = try? credentialStore.load()
        self.credentials = credentials
        serverURL = credentials?.serverURL
        phase = credentials == nil ? .signedOut : .connecting
    }

    /// A store filled with sample data, for previews and the `-demo` launch argument.
    init(demo states: [EntityState], layout: HomeLayout, household: HouseholdStore, phase: Phase = .connected) {
        credentialStore = CredentialStore(service: "com.theodaguier.maison.demo")
        self.household = household
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

    // MARK: - Session

    func start() async {
        guard !isDemo else { return }
        Task { await household.start() }
        // Without credentials, onboarding starts discovery once it has explained why it needs the local network.
        if credentials != nil {
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
        if let serverURL {
            await household.serverConnected(Household(
                name: serverConfig?.locationName ?? String(localized: "Home"),
                serverURL: serverURL,
                remoteURL: serverConfig?.externalURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
            ))
        }
    }

    /// How long the device was on today and yesterday.
    func usage(of entity: EntityState) async -> (today: DayUsage, yesterday: DayUsage)? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return nil }
        let today = DateInterval(start: todayStart, duration: 86_400)
        let yesterday = DateInterval(start: yesterdayStart, end: todayStart)

        if isDemo {
            func period(_ from: Double, _ to: Double, in day: DateInterval) -> DateInterval {
                DateInterval(start: day.start.addingTimeInterval(from * 3600), end: day.start.addingTimeInterval(to * 3600))
            }
            return (
                DayUsage(periods: [period(6.5, 7.2, in: today), period(15.8, 17.2, in: today)], day: today),
                DayUsage(periods: [period(6.6, 7.4, in: yesterday), period(18, 21.5, in: yesterday)], day: yesterday)
            )
        }
        guard let connection, let changes = try? await connection.history(of: entity.entityID, since: yesterdayStart) else {
            return nil
        }
        let todayChanges = Self.changes(changes, startingAt: todayStart)
        return (DayUsage(changes: todayChanges, day: today), DayUsage(changes: changes, day: yesterday))
    }

    /// How much a sensor's value differs from its value at the same time yesterday.
    func changeSinceYesterday(of entity: EntityState) async -> Double? {
        guard let current = entity.numericState else { return nil }
        if isDemo { return -0.6 }
        let sameTimeYesterday = Date.now.addingTimeInterval(-86_400)
        guard
            let connection,
            let changes = try? await connection.history(of: entity.entityID, since: sameTimeYesterday.addingTimeInterval(-3600)),
            let then = changes.last(where: { $0.date <= sameTimeYesterday }).flatMap({ Double($0.state) })
        else { return nil }
        return current - then
    }

    /// Keeps the changes from `start`, prefixed with the state that was current at `start`.
    private static func changes(_ changes: [StateChange], startingAt start: Date) -> [StateChange] {
        let before = changes.last { $0.date <= start }
        return (before.map { [StateChange(state: $0.state, date: start)] } ?? []) + changes.filter { $0.date > start }
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

    // MARK: - Device details

    /// State changes since `start`, oldest first; the first entry is the state at `start`.
    func changes(of entityID: String, since start: Date) async -> [StateChange] {
        if isDemo { return DemoHome.changes(of: entityID, since: start) }
        guard let connection else { return [] }
        return (try? await connection.history(of: entityID, since: start)) ?? []
    }

    func logbook(of entityID: String, since start: Date) async -> [LogbookEntry] {
        if isDemo { return DemoHome.logbook(of: entityID) }
        guard let connection else { return [] }
        return (try? await connection.logbook(of: entityID, since: start)) ?? []
    }

    func statistics(of entityID: String, since start: Date, period: String) async -> [StatisticPoint] {
        if isDemo { return DemoHome.statistics(of: entityID, since: start, period: period) }
        guard let connection else { return [] }
        return (try? await connection.statistics(of: entityID, since: start, period: period)) ?? []
    }

    /// Automations that act on or watch the entity.
    func automations(using entity: EntityState) async -> [EntityState] {
        if isDemo { return entity.kind == .cover ? [states["automation.trop_chaud"]].compactMap { $0 } : [] }
        guard let connection, let ids = try? await connection.automations(using: entity.entityID) else { return [] }
        return ids.compactMap { states[$0] }
    }

    /// Saves automations and scripts on the server; `nil` when signed out or in the demo.
    var configEditor: ConfigEditor? {
        guard !isDemo, let credentials else { return nil }
        return ConfigEditor(serverURL: credentials.serverURL, accessToken: credentials.accessToken)
    }

    /// Notify services available on the server (`mobile_app_iphone_de_theo`, `notify`).
    func notifyServices() async -> [String] {
        if isDemo { return ["mobile_app_iphone"] }
        guard let connection, let services = try? await connection.send(["type": "get_services"]) else { return [] }
        return services["notify"]?.objectValue.map { Array($0.keys).sorted() } ?? []
    }

    /// NFC tags registered in Home Assistant, by id, with their name when they have one.
    func tags() async -> [(id: String, name: String)] {
        var tags: [(id: String, name: String)] = [("entree", "Entrée"), ("table-de-nuit", "Table de nuit")]
        if !isDemo {
            guard let connection, let list = try? await connection.send(["type": "tag/list"]) else { return [] }
            tags = (list.arrayValue ?? []).compactMap { tag in
                guard let id = tag["id"]?.stringValue else { return nil }
                return (id, tag["name"]?.stringValue ?? id)
            }
        }
        tagNames = Dictionary(tags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return tags
    }

    func runScript(_ scriptID: String, variables: [String: JSONValue] = [:]) async throws {
        guard !isDemo else { return }
        guard let connection else { throw HomeAssistantError.connectionClosed }
        try await connection.callService(domain: "script", service: "turn_on", entityID: "script.\(scriptID)",
                                         data: variables.isEmpty ? [:] : ["variables": .object(variables)])
    }

    func stopScript(_ scriptID: String) async {
        guard !isDemo, let connection else { return }
        try? await connection.callService(domain: "script", service: "turn_off", entityID: "script.\(scriptID)")
    }

    // MARK: - Presence

    /// Registers Maison as a mobile app device for the signed-in user (`/api/mobile_app/registrations`).
    func registerMobileApp(deviceName: String) async throws -> Webhook {
        if isDemo { return Webhook(id: "demo", localURL: nil, remoteURL: nil) }
        guard let credentials else { throw HomeAssistantError.connectionClosed }
        var request = URLRequest(url: credentials.serverURL.appending(path: "api/mobile_app/registrations"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "device_id": .string(UUID().uuidString),
            "app_id": "com.theodaguier.maison",
            "app_name": "Maison",
            "app_version": .string(version),
            "device_name": .string(deviceName),
            "manufacturer": "Apple",
            "model": "iPhone",
            "os_name": "iOS",
            "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "supports_encryption": false,
        ]))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let id = try JSONDecoder().decode(JSONValue.self, from: data)["webhook_id"]?.stringValue else {
            throw HomeAssistantError.invalidResponse(statusCode: status)
        }
        let remote = serverConfig?.externalURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return Webhook(id: id, localURL: credentials.serverURL, remoteURL: remote)
    }

    /// Adds the iPhone's tracker to the person linked to the signed-in user, so they count as home or away.
    func attachTracker(webhookID: String) async throws {
        guard !isDemo, let connection, let userID = currentUser?.id else { return }
        let entities = try await connection.send(["type": "config/entity_registry/list"])
        guard let tracker = entities.arrayValue?.first(where: {
            $0["platform"]?.stringValue == "mobile_app" && $0["unique_id"]?.stringValue == webhookID
                && $0["entity_id"]?.stringValue?.hasPrefix("device_tracker.") == true
        })?["entity_id"]?.stringValue else { return }
        let persons = try await connection.send(["type": "person/list"])
        guard let person = persons["storage"]?.arrayValue?.first(where: { $0["user_id"]?.stringValue == userID }),
              let personID = person["id"]?.stringValue else { return }
        let trackers = person["device_trackers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        guard !trackers.contains(tracker) else { return }
        _ = try await connection.send([
            "type": "person/update",
            "person_id": .string(personID),
            "device_trackers": .array((trackers + [tracker]).map { .string($0) }),
        ])
    }

    /// Whether the signed-in user's person already has a tracker (often Home Assistant's own app).
    var isTrackedByHomeAssistant: Bool {
        guard let userID = currentUser?.id else { return false }
        return states.values.contains {
            $0.domain == "person" && $0.attributes["user_id"]?.stringValue == userID
                && !($0.attributes["device_trackers"]?.arrayValue?.isEmpty ?? true)
        }
    }

    // MARK: - Automations

    /// Recent runs of every automation, from the traces Home Assistant keeps.
    func automationRuns() async -> [AutomationRun] {
        if isDemo { return DemoHome.runs }
        guard let connection else { return [] }
        return (try? await connection.automationRuns()) ?? []
    }

    /// The rule behind an automation entity, or `nil` when it isn't stored in the UI editor's file.
    func rule(for automation: EntityState) async throws -> AutomationRule? {
        guard let id = automation.attributes["id"]?.stringValue else { return nil }
        if isDemo { return DemoHome.rules[id].map { AutomationRule(id: id, config: $0) } }
        guard let editor = configEditor else { throw HomeAssistantError.connectionClosed }
        return try await editor.load(.automation, id: id).map { AutomationRule(id: id, config: $0) }
    }

    func save(_ rule: AutomationRule) async throws {
        if isDemo {
            DemoHome.rules[rule.id] = rule.config
            return
        }
        guard let editor = configEditor else { throw HomeAssistantError.connectionClosed }
        try await editor.save(.automation, id: rule.id, config: rule.config)
    }

    func delete(_ rule: AutomationRule) async throws {
        if isDemo { return }
        guard let editor = configEditor else { throw HomeAssistantError.connectionClosed }
        try await editor.delete(.automation, id: rule.id)
    }

    // MARK: - Actions

    func call(_ domain: String, _ service: String, on entity: EntityState, data: [String: JSONValue] = [:]) async {
        if isDemo {
            // The sample home answers like a server would, so the demo can be used for real.
            if let updated = DemoHome.applying(domain, service, to: entity, data: data) {
                states[entity.entityID] = updated
            }
            return
        }
        guard let connection else { return }
        do {
            try await connection.callService(domain: domain, service: service, entityID: entity.entityID, data: data)
        } catch HomeAssistantError.connectionClosed {
            failedCommands += 1
            connectionLost()
        } catch {
            // Rejected calls leave the state unchanged; the live update stream shows the truth.
            failedCommands += 1
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

    var favoriteIDs: [String] { household.favoriteIDs }

    func toggleFavorite(_ entity: EntityState) {
        household.toggleFavorite(entity.entityID)
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

    /// One entry per integration, with how many times it is set up, by name.
    var integrationSummaries: [IntegrationSummary] {
        Dictionary(grouping: integrations, by: \.domain)
            .map { IntegrationSummary(domain: $0.key, title: $0.value.first?.title ?? $0.key, count: $0.value.count) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Entities kept out of the app: hidden in Home Assistant or of no use to someone at home.
    var technicalEntityCount: Int {
        states.values.filter { layout.hiddenEntities.contains($0.entityID) || $0.kind == .other || $0.kind == .button }.count
    }

    var lightsOn: [EntityState] {
        devices.filter { $0.kind == .light && $0.state == "on" }
    }

    var indoorTemperatureSensors: [EntityState] {
        devices.filter {
            $0.kind == .sensor && $0.deviceClass == "temperature" && $0.numericState != nil
                && !$0.name.lowercased().contains("ext") && !$0.name.lowercased().contains("out")
        }
    }

    /// The temperature shown in the hero ring, with where it comes from.
    var heroTemperature: HeroTemperature? {
        let indoorSensors = indoorTemperatureSensors
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

    /// The sentences of the home summary card, most important first.
    /// `temperatureChange` is the indoor temperature compared with the same time yesterday.
    func summary(temperatureChange: Double? = nil) -> HomeSummary {
        var sentences: [String] = []
        let locks = devices.filter { $0.kind == .lock }
        let openings = devices.filter { $0.kind == .binarySensor && ["door", "window", "garage_door", "opening"].contains($0.deviceClass ?? "") && $0.isActive }
        let unlocked = locks.filter { $0.state == "unlocked" }

        for lock in unlocked {
            sentences.append(String(localized: "\(Phrasing.subject(lock.name)) is unlocked."))
        }
        for opening in openings {
            sentences.append(String(localized: "\(Phrasing.subject(opening.name)) is open."))
        }
        if let lock = locks.first(where: { $0.state == "locked" }), unlocked.isEmpty {
            if let since = lock.lastChanged {
                sentences.append(String(localized: "\(Phrasing.subject(lock.name)) has been locked since \(Phrasing.time(since))."))
            } else {
                sentences.append(String(localized: "\(Phrasing.subject(lock.name)) is locked."))
            }
        }

        let lights = lightsOn
        if lights.isEmpty {
            sentences.append(String(localized: "All lights are off."))
        } else {
            let rooms = Set(lights.compactMap { area(of: $0)?.name })
            let room = rooms.count == 1 ? rooms.first : nil
            switch (lights.count, room) {
            case (1, let room?):
                sentences.append(String(localized: "One light is on, \(Phrasing.location(room))."))
            case (1, nil):
                sentences.append(String(localized: "One light is on."))
            case (_, let room?):
                sentences.append(String(localized: "\(Phrasing.count(lights.count, capitalized: true)) lights are on, all \(Phrasing.location(room))."))
            default:
                sentences.append(String(localized: "\(Phrasing.count(lights.count, capitalized: true)) lights are on, in \(rooms.count) rooms."))
            }
        }

        if let change = temperatureChange {
            let degrees = abs(change).formatted(.number.precision(.fractionLength(1)))
            if abs(change) < 0.3 {
                sentences.append(String(localized: "Same temperature as yesterday at this time."))
            } else if change > 0 {
                sentences.append(String(localized: "It’s \(degrees)° warmer than yesterday at this time."))
            } else {
                sentences.append(String(localized: "It’s \(degrees)° cooler than yesterday at this time."))
            }
        }

        // Shown once the card is expanded.
        var more: [String] = []
        for player in devices.filter({ $0.kind == .mediaPlayer && $0.state == "playing" }) {
            if let title = player.attributes["media_title"]?.stringValue {
                more.append(String(localized: "\(player.name) is playing “\(title)”."))
            } else {
                more.append(String(localized: "\(player.name) is playing."))
            }
        }
        for climate in devices.filter({ $0.kind == .climate && $0.state != "off" }) {
            if let target = climate.targetTemperature {
                more.append(String(localized: "\(Phrasing.subject(climate.name)) is set to \(EntityState.degrees(target))."))
            }
        }
        let silent = devices.filter(\.isUnavailable)
        if !silent.isEmpty {
            more.append(String(localized: "\(silent.count) devices aren’t responding: \(silent.map(\.name).formatted(.list(type: .and)))."))
        }

        let isCalm = unlocked.isEmpty && openings.isEmpty
        return HomeSummary(
            title: isCalm ? String(localized: "All Quiet at Home") : String(localized: "Worth a Look"),
            sentences: sentences,
            more: more,
            isCalm: isCalm
        )
    }

    /// How much warmer the indoor sensors are than at the same time yesterday.
    func temperatureChangeSinceYesterday() async -> Double? {
        if isDemo { return 1.2 }
        var changes: [Double] = []
        for sensor in indoorTemperatureSensors {
            if let change = await changeSinceYesterday(of: sensor) { changes.append(change) }
        }
        return changes.isEmpty ? nil : changes.reduce(0, +) / Double(changes.count)
    }
}

struct IntegrationSummary: Equatable {
    let domain: String
    let title: String
    let count: Int
}

struct HeroTemperature: Equatable {
    enum Source { case indoor, outdoor }
    let value: Double
    let source: Source
}

struct HomeSummary: Equatable {
    let title: String
    let sentences: [String]
    /// Details that don't need attention, shown once the card is expanded.
    var more: [String] = []
    let isCalm: Bool

    var text: String { sentences.joined(separator: " ") }
}

extension Sequence where Element == EntityState {
    func sortedByName() -> [EntityState] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
