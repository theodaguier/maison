import SwiftUI

/// What the + next to the tabs offers, from any screen. Only actions that work today are shown: the
/// others (scan a document, "I'm leaving", add a device) come with their journeys.
enum PlusAction: String, CaseIterable, Identifiable {
    case describeRule, newRule, scene, turnOff, testInternet, search

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .describeRule: "Describe a Rule"
        case .newRule: "Create a Rule"
        case .scene: "Run a Scene"
        case .turnOff: "Turn Everything Off"
        case .testInternet: "Test the Internet"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .describeRule: "sparkles"
        case .newRule: "switch.2"
        case .scene: "sun.horizon.fill"
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
        case .newRule, .search: true
        case .scene: !store.scenes.isEmpty
        case .turnOff: !store.devicesToTurnOff.isEmpty
        case .testInternet: store.internetSources != nil
        }
    }
}

/// A screen an action opens once the panel closes.
enum QuickSheet: String, Identifiable {
    case describeRule, newRule, scenes, search
    var id: String { rawValue }
}

/// The panel above the tab bar. Touching outside it, or the ×, closes it.
struct QuickActionsPanel: View {
    @Environment(HomeStore.self) private var store
    @Binding var isPresented: Bool
    let open: (QuickSheet) -> Void
    @State private var confirmsTurnOff = false
    @State private var internetResult: String?
    @State private var isTesting = false
    @State private var turnedOff = 0

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
                    turnedOff += 1
                    isPresented = false
                }
            }
        } message: {
            Text("Lights, plugs, fans and speakers. Devices set to “Never Turn Off” stay on.")
        }
        .sensoryFeedback(.success, trigger: turnedOff)
    }

    private var card: some View {
        let actions = PlusAction.allCases.filter { $0.isAvailable(in: store) }
        return VStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), spacing: 22) {
                ForEach(actions) { action in
                    Button { perform(action) } label: { tile(action) }
                        .buttonStyle(.pressable)
                }
            }
            if let internetResult {
                Text(internetResult)
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 34))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 10)
        .animation(.smooth, value: internetResult)
    }

    private func tile(_ action: PlusAction) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                if action == .testInternet, isTesting {
                    ProgressView()
                } else {
                    Image(systemName: action.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 64, height: 64)
            Text(action.title)
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    private func perform(_ action: PlusAction) {
        switch action {
        case .describeRule: open(.describeRule)
        case .newRule: open(.newRule)
        case .scene: open(.scenes)
        case .search: open(.search)
        case .turnOff: confirmsTurnOff = true
        case .testInternet: Task { await testInternet() }
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
