import SwiftUI

/// Maison's own actions in the + panel. Devices, scenes and rules join them as `Shortcut.entity`.
enum PlusAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case describeRule, leaving, scene, addDevice, newRule, turnOff, testInternet, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .describeRule: String(localized: "Describe a Rule")
        case .leaving: String(localized: "I’m Leaving")
        case .scene: String(localized: "Run a Scene")
        case .addDevice: String(localized: "Add a Device")
        case .newRule: String(localized: "Create a Rule")
        case .turnOff: String(localized: "Turn Everything Off")
        case .testInternet: String(localized: "Test the Internet")
        case .search: String(localized: "Search")
        }
    }

    var symbol: String {
        switch self {
        case .describeRule: "sparkles"
        case .leaving: "figure.walk.departure"
        case .scene: "sun.horizon.fill"
        case .addDevice: "plus.viewfinder"
        case .newRule: "switch.2"
        case .turnOff: "power"
        case .testInternet: "wifi"
        case .search: "magnifyingglass"
        }
    }

    /// Whether the action can do something in this home right now.
    @MainActor
    func isAvailable(in store: HomeStore) -> Bool {
        switch self {
        case .describeRule: Intelligence.isAvailable
        case .leaving, .newRule, .search, .addDevice: true
        case .scene: !store.scenes.isEmpty
        case .turnOff: !store.devicesToTurnOff.isEmpty
        case .testInternet: store.internetSources != nil
        }
    }
}

/// A screen an action opens once the panel closes.
enum QuickSheet: String, Identifiable {
    case describeRule, newRule, scenes, search, leaving, addDevice, editShortcuts
    var id: String { rawValue }
}

extension HomeStore {
    /// What a shortcut stands for, while it still exists in this home.
    func shortcutEntity(_ entityID: String) -> EntityState? { states[entityID] }

    func isAvailable(_ shortcut: Shortcut) -> Bool {
        switch shortcut {
        case .action(let action): action.isAvailable(in: self)
        case .entity(let entityID): states[entityID] != nil
        }
    }

    /// Runs a pinned device, scene or rule the way its own control would.
    func perform(shortcutFor entity: EntityState) async {
        switch entity.domain {
        case "scene": await call("scene", "turn_on", on: entity)
        case "automation": await call("automation", "trigger", on: entity)
        case "script": await call("script", "turn_on", on: entity)
        case "lock": await call("lock", entity.state == "locked" ? "unlock" : "lock", on: entity)
        default: await performPrimaryAction(on: entity)
        }
    }
}

// MARK: - Panel

/// The panel above the tab bar: six shortcuts a page, the page dots and "Edit". Touching outside it,
/// or the ×, closes it.
struct QuickActionsPanel: View {
    @Environment(HomeStore.self) private var store
    @Binding var isPresented: Bool
    let open: (QuickSheet) -> Void
    @AppStorage(ShortcutList.key) private var stored: Data?
    @State private var page = 0
    @State private var confirmsTurnOff = false
    @State private var internetResult: String?
    @State private var isTesting = false
    @State private var done = 0

    /// Room for the tab bar, which stays live under the panel: its × closes it.
    static let tabBarHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 0) {
            Theme.background.opacity(0.72)
                .contentShape(.rect)
                .onTapGesture { isPresented = false }
                .overlay(alignment: .bottom) { card.padding(.horizontal, Theme.screenPadding).padding(.bottom, 12) }
            Color.clear
                .frame(height: Self.tabBarHeight)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .confirmationDialog("Turn Everything Off?", isPresented: $confirmsTurnOff, titleVisibility: .visible) {
            Button("Turn Off \(store.devicesToTurnOff.count) Devices", role: .destructive) {
                Task {
                    await store.turnEverythingOff()
                    done += 1
                    isPresented = false
                }
            }
        } message: {
            Text("Lights, plugs, fans and speakers. Devices set to “Never Turn Off” stay on.")
        }
        .sensoryFeedback(.success, trigger: done)
    }

    private var shortcuts: [Shortcut] {
        let all = stored.flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) }
            ?? ShortcutList.starting(favorites: store.favorites.map(\.entityID))
        return all.filter { store.isAvailable($0) }
    }

    /// Shortcuts, then one "Add" slot while there is room for more.
    private var slots: [Slot] {
        let shortcuts = shortcuts.map(Slot.shortcut)
        return shortcuts.count < ShortcutList.capacity ? shortcuts + [.add] : shortcuts
    }

    private enum Slot: Hashable, Identifiable {
        case shortcut(Shortcut)
        case add
        var id: String {
            switch self {
            case .shortcut(let shortcut): shortcut.id
            case .add: "add"
            }
        }
    }

    private var card: some View {
        let pages = ShortcutList.pages(slots)
        return VStack(spacing: 14) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, items in
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), spacing: 20) {
                        ForEach(items) { slot in
                            switch slot {
                            case .shortcut(let shortcut):
                                Button { perform(shortcut) } label: { tile(for: shortcut) }
                                    .buttonStyle(.pressable)
                            case .add:
                                Button { open(.editShortcuts) } label: { addTile }
                                    .buttonStyle(.pressable)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 236)
            if let internetResult {
                Text(internetResult)
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            HStack {
                Spacer()
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                .opacity(pages.count > 1 ? 1 : 0)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Edit") { open(.editShortcuts) }
                    .font(.roundedSubheadlineEmphasized)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 34))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 10)
        .animation(.smooth, value: internetResult)
        .animation(.smooth, value: page)
    }

    @ViewBuilder
    private func tile(for shortcut: Shortcut) -> some View {
        switch shortcut {
        case .action(let action):
            tile(symbol: action.symbol, title: action.title, isBusy: action == .testInternet && isTesting)
        case .entity(let entityID):
            let entity = store.shortcutEntity(entityID)
            tile(symbol: entity?.symbolName ?? "questionmark", title: entity?.name ?? "", isBusy: false)
        }
    }

    private func tile(symbol: String, title: String, isBusy: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 64, height: 64)
            Text(title)
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    private var addTile: some View {
        VStack(spacing: 10) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 64, height: 64)
            Text("Add")
                .font(.roundedSubheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    private func perform(_ shortcut: Shortcut) {
        switch shortcut {
        case .action(.describeRule): open(.describeRule)
        case .action(.leaving): open(.leaving)
        case .action(.scene): open(.scenes)
        case .action(.addDevice): open(.addDevice)
        case .action(.newRule): open(.newRule)
        case .action(.search): open(.search)
        case .action(.turnOff): confirmsTurnOff = true
        case .action(.testInternet): Task { await testInternet() }
        case .entity(let entityID):
            guard let entity = store.shortcutEntity(entityID) else { return }
            Task {
                await store.perform(shortcutFor: entity)
                done += 1
            }
        }
    }

    /// Asks the server's internet check to run now, then says what it found.
    private func testInternet() async {
        guard let source = store.internetSources, !isTesting else { return }
        isTesting = true
        defer { isTesting = false }
        await store.call("homeassistant", "update_entity", on: source.connectivity)
        if let latency = source.latency { await store.call("homeassistant", "update_entity", on: latency) }
        try? await Task.sleep(for: .seconds(2))
        guard let now = store.internetSources else { return }
        if now.connectivity.state == "on" {
            internetResult = now.latency?.numericState.map { String(localized: "The internet answers in \(Int($0.rounded())) ms") }
                ?? String(localized: "The internet answers")
        } else {
            internetResult = String(localized: "The internet doesn’t answer")
        }
    }
}

// MARK: - Shortcuts

/// "Edit": twelve shortcuts at most on two pages. Remove, add, drag to reorder.
struct ShortcutsEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shortcuts: [Shortcut] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EmptyView()
                } footer: {
                    Text("Up to 12 shortcuts on two pages. Drag a row to change the order.")
                        .font(.roundedFootnote)
                }
                ForEach(Array(ShortcutList.pages(shortcuts).enumerated()), id: \.offset) { index, items in
                    Section {
                        ForEach(items) { shortcut in row(for: shortcut) }
                            .onDelete { offsets in remove(offsets, page: index) }
                            .onMove { from, to in move(from, to, page: index) }
                    } header: {
                        HStack {
                            Text("Page \(index + 1)").font(.roundedHeadline).foregroundStyle(.primary)
                            Spacer()
                            Text("\(items.count) of \(ShortcutList.perPage)").font(.roundedFootnote).foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                }
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { shortcut in
                            Button { add(shortcut) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.green)
                                    label(for: shortcut)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(shortcuts.count >= ShortcutList.capacity)
                        }
                    } header: {
                        Text("Add").font(.roundedHeadline).foregroundStyle(.primary).textCase(nil)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Finish Editing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .font(.roundedHeadline)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 8)
            }
            .onChange(of: shortcuts) { _, new in ShortcutList.save(new) }
            .onAppear {
                shortcuts = (ShortcutList.load() ?? ShortcutList.starting(favorites: store.favorites.map(\.entityID)))
                    .filter { store.isAvailable($0) }
            }
        }
    }

    private func row(for shortcut: Shortcut) -> some View {
        label(for: shortcut)
    }

    private func label(for shortcut: Shortcut) -> some View {
        let (symbol, title) = describe(shortcut)
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Theme.pill, in: .circle)
            Text(title).font(.roundedBody)
        }
    }

    private func describe(_ shortcut: Shortcut) -> (String, String) {
        switch shortcut {
        case .action(let action): return (action.symbol, action.title)
        case .entity(let entityID):
            guard let entity = store.shortcutEntity(entityID) else { return ("questionmark", entityID) }
            switch entity.domain {
            case "scene": return (entity.symbolName, String(localized: "Run “\(entity.name)”"))
            case "automation": return ("switch.2", String(localized: "A rule: \(entity.name)"))
            default: return (entity.symbolName, entity.name)
            }
        }
    }

    /// Maison's actions not used yet, then scenes, rules and the devices with a one-tap control.
    private var suggestions: [Shortcut] {
        let used = Set(shortcuts)
        let actions = PlusAction.allCases.filter { $0.isAvailable(in: store) }.map(Shortcut.action)
        let favorites = store.favoriteIDs
        let devices = store.devices
            .filter { [.light, .switch, .lock, .cover, .fan, .mediaPlayer].contains($0.kind) }
            .sorted { (favorites.contains($0.entityID) ? 0 : 1, $0.name) < (favorites.contains($1.entityID) ? 0 : 1, $1.name) }
        let entities = (store.scenes + store.automations + devices).map { Shortcut.entity($0.entityID) }
        return (actions + entities).filter { !used.contains($0) }
    }

    private func remove(_ offsets: IndexSet, page: Int) {
        let base = page * ShortcutList.perPage
        shortcuts.remove(atOffsets: IndexSet(offsets.map { $0 + base }))
    }

    private func move(_ from: IndexSet, _ to: Int, page: Int) {
        let base = page * ShortcutList.perPage
        shortcuts.move(fromOffsets: IndexSet(from.map { $0 + base }), toOffset: to + base)
    }

    private func add(_ shortcut: Shortcut) {
        guard shortcuts.count < ShortcutList.capacity, !shortcuts.contains(shortcut) else { return }
        shortcuts.append(shortcut)
    }
}

// MARK: - Leaving

/// What leaving means for this home: what only the person can do, and what Maison does on its own.
struct LeavingPlan: Equatable {
    /// Windows and doors still open, locks still open.
    var toSettle: [EntityState]
    var lights: [EntityState]
    /// Heating or cooling that has an away or eco preset Maison can switch to.
    var climate: [(entity: EntityState, preset: String)]
    var waterHeaters: [EntityState]
    var media: [EntityState]

    init(devices: [EntityState]) {
        let openings: Set = ["window", "door", "opening", "garage_door"]
        toSettle = devices.filter {
            ($0.kind == .binarySensor && openings.contains($0.deviceClass ?? "") && $0.state == "on")
                || ($0.kind == .lock && $0.state == "unlocked")
        }
        lights = devices.filter { $0.kind == .light && $0.state == "on" }
        climate = devices.compactMap { entity in
            guard entity.domain == "climate", entity.state != "off" else { return nil }
            let presets = entity.attributes["preset_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard let preset = ["away", "eco"].first(where: presets.contains),
                  entity.attributes["preset_mode"]?.stringValue != preset else { return nil }
            return (entity, preset)
        }
        waterHeaters = devices.filter { $0.domain == "water_heater" && $0.state != "off" }
        media = devices.filter { $0.kind == .mediaPlayer && $0.state == "playing" }
    }

    var isEmpty: Bool { lights.isEmpty && climate.isEmpty && waterHeaters.isEmpty && media.isEmpty }

    @MainActor
    func run(on store: HomeStore) async {
        for light in lights { await store.call("light", "turn_off", on: light) }
        for (entity, preset) in climate { await store.call("climate", "set_preset_mode", on: entity, data: ["preset_mode": .string(preset)]) }
        for heater in waterHeaters { await store.call("water_heater", "turn_off", on: heater) }
        for player in media { await store.call("media_player", "media_pause", on: player) }
    }

    static func == (lhs: LeavingPlan, rhs: LeavingPlan) -> Bool {
        lhs.toSettle == rhs.toSettle && lhs.lights == rhs.lights && lhs.waterHeaters == rhs.waterHeaters && lhs.media == rhs.media
            && lhs.climate.map(\.entity) == rhs.climate.map(\.entity) && lhs.climate.map(\.preset) == rhs.climate.map(\.preset)
    }
}

/// When Maison last put the home in away mode, for the home screen to say so.
enum AwayMode {
    static let key = "awayModeSince"
    static var since: Date? { UserDefaults.standard.object(forKey: key) as? Date }
}

/// "I'm leaving": first what to do yourself, then what Maison will do, then away mode.
struct LeavingSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var closed: Set<String> = []
    @State private var isRunning = false
    @State private var done = 0

    var body: some View {
        let plan = LeavingPlan(devices: store.devices)
        let toSettle = plan.toSettle.filter { !closed.contains($0.entityID) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Before Leaving").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(toSettle.isEmpty
                            ? String(localized: "Nothing to do yourself. The rest happens on its own.")
                            : String(localized: "\(toSettle.count) things to do yourself. The rest happens on its own."))
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !toSettle.isEmpty {
                        rows(toSettle.map { entity in settleRow(entity) })
                    }
                    Text("What Maison Will Do").font(.roundedTitle3).padding(.top, 4)
                    rows(plannedRows(plan))
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("I’m Leaving")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        isRunning = true
                        await plan.run(on: store)
                        UserDefaults.standard.set(Date.now, forKey: AwayMode.key)
                        isRunning = false
                        done += 1
                        dismiss()
                    }
                } label: {
                    Group {
                        if isRunning { ProgressView() } else { Text("Turn On Away Mode") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .font(.roundedHeadline)
                .disabled(isRunning)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 8)
            }
            .sensoryFeedback(.success, trigger: done)
        }
    }

    private func rows(_ items: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 64) }
                item
            }
        }
        .cardStyle()
    }

    private func settleRow(_ entity: EntityState) -> AnyView {
        let isLock = entity.kind == .lock
        return AnyView(HStack(spacing: 14) {
            badge(symbol: isLock ? "lock.open.fill" : entity.symbolName, color: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name).font(.roundedHeadline)
                Text(isLock ? String(localized: "Unlocked") : String(localized: "Open"))
                    .font(.roundedFootnote)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 8)
            Button(isLock ? String(localized: "Lock") : String(localized: "I Closed It")) {
                if isLock {
                    Task { await store.call("lock", "lock", on: entity) }
                } else {
                    withAnimation(.smooth) { _ = closed.insert(entity.entityID) }
                }
            }
            .font(.roundedSubheadlineEmphasized)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12))
    }

    private func plannedRows(_ plan: LeavingPlan) -> [AnyView] {
        var result: [AnyView] = []
        if !plan.lights.isEmpty {
            result.append(planned(symbol: "lamp.floor.fill", color: .yellow, title: String(localized: "Lights"),
                                  detail: String(localized: "\(plan.lights.count) on, turned off as you leave")))
        }
        for (entity, preset) in plan.climate {
            result.append(planned(symbol: "thermometer.medium", color: .orange, title: entity.name,
                                  detail: preset == "away" ? String(localized: "Set to away") : String(localized: "Set to eco")))
        }
        for heater in plan.waterHeaters {
            result.append(planned(symbol: "drop.fill", color: .yellow, title: heater.name, detail: String(localized: "Off while you’re away")))
        }
        if !plan.media.isEmpty {
            result.append(planned(symbol: "speaker.wave.2.fill", color: .indigo, title: String(localized: "Music and TV"),
                                  detail: String(localized: "\(plan.media.count) playing, paused")))
        }
        if result.isEmpty {
            result.append(planned(symbol: "checkmark", color: .green, title: String(localized: "Everything is already off"),
                                  detail: String(localized: "Away mode notes when you left.")))
        }
        return result
    }

    private func planned(symbol: String, color: Color, title: String, detail: String) -> AnyView {
        AnyView(HStack(spacing: 14) {
            badge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.roundedHeadline)
                Text(detail).font(.roundedFootnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12))
    }

    private func badge(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(color, in: .rect(cornerRadius: 9))
    }
}

// MARK: - Add a device

/// "Add a Device": Maison adds what Home Assistant found on the network right away, and says what it did.
struct AddDeviceSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var result: (added: [String], waiting: [String])?
    @State private var isSearching = true
    @State private var noAccess = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for devices on your network…").font(.roundedHeadline)
                    }
                } else if noAccess {
                    message(symbol: "person.badge.key.fill", title: String(localized: "Waiting for an Administrator"),
                            detail: String(localized: "Maison adds devices with an administrator’s account. It does so the next time an administrator opens Maison."))
                } else if let result, !result.added.isEmpty {
                    message(symbol: "checkmark.circle.fill", title: String(localized: "Added to Your Home"),
                            detail: result.added.map(name).formatted(.list(type: .and)))
                } else {
                    message(symbol: "dot.radiowaves.left.and.right", title: String(localized: "Nothing New on Your Network"),
                            detail: String(localized: "Plug in the device and connect it to your Wi-Fi with its own app. Maison checks your network regularly and adds it by itself."))
                }
                if let waiting = result?.waiting, !waiting.isEmpty {
                    Text("Found, waiting for a pairing code: \(waiting.map(name).formatted(.list(type: .and)))")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(Theme.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .navigationTitle("Add a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                result = await store.addFoundDevices()
                noAccess = result == nil
                isSearching = false
            }
        }
        .presentationDetents([.medium])
    }

    private func name(_ domain: String) -> String {
        store.integrations.first { $0.domain == domain }?.title ?? domain.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.secondary)
            Text(title).font(.roundedTitle3)
            Text(detail).font(.roundedSubheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Scenes and search

/// The household's scenes, from the + anywhere in the app.
struct ScenesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ScenesSection()
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Every device, searchable by name or room.
struct DeviceSearchSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var opened: OpenedDevice?

    var body: some View {
        NavigationStack {
            List(results) { entity in
                Button { opened = OpenedDevice(id: entity.entityID) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entity.name).font(.roundedHeadline).foregroundStyle(.primary)
                            if let room = store.area(of: entity)?.name {
                                Text(room).font(.roundedFootnote).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: entity.symbolName).foregroundStyle(entity.accent)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if results.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Devices and rooms"))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
        }
    }

    private var results: [EntityState] {
        let devices = store.devices.sortedByName()
        guard !query.isEmpty else { return devices }
        return devices.filter {
            $0.name.localizedStandardContains(query) || (store.area(of: $0)?.name.localizedStandardContains(query) ?? false)
        }
    }
}
