import SwiftUI

struct HomeView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        NavigationStack {
            switch store.phase {
            case .signedOut:
                ConnectView()
                    .navigationTitle("Home")
            case .connecting where store.states.isEmpty:
                ProgressView("Connecting…")
                    .navigationTitle("Home")
            case .failed(let message) where store.states.isEmpty:
                ConnectionErrorView(message: message)
                    .navigationTitle("Home")
            default:
                HomeDashboard()
            }
        }
    }
}

struct ConnectionErrorView: View {
    @Environment(HomeStore.self) private var store
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Connect", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await store.connect() }
            }
            .buttonStyle(.glassProminent)
        }
    }
}

/// Opens a device sheet from anywhere in a screen.
struct OpenedDevice: Identifiable {
    let id: String
}

private struct HomeDashboard: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var opened: OpenedDevice?
    @State private var showsAllScenes = false
    /// Height of the navigation bar area above the scroll content; the hero extends under it.
    @State private var topInset: CGFloat = 0
    /// The bar gets its opaque edge only once the illustration has scrolled away.
    @State private var isPastHero = false

    private let heroHeight: CGFloat = 480
    /// Space between the large-title bar and the first card (design: cards start at 438 pt, bar ends at 187 pt).
    private let heroSpace: CGFloat = 251

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                hero
                metrics
                SummaryCard(summary: store.summary)
                scenes
                favorites
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
            .background(alignment: .top) { illustration.offset(y: -topInset) }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentInsets.top }) { _, inset in
            topInset = inset
        }
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 300 }) { _, isPast in
            isPastHero = isPast
        }
        .scrollEdgeEffectHidden(!isPastHero, for: .top)
        .background(Theme.background)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle(store.serverConfig?.locationName ?? String(localized: "Home"))
        .navigationSubtitle(Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute()))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let serverURL = store.serverURL {
                    Button("Add in Home Assistant", systemImage: "plus") {
                        openURL(serverURL.appending(path: "config/integrations/dashboard"))
                    }
                }
                Menu("More", systemImage: "ellipsis") {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.connect() }
                    }
                    if let serverURL = store.serverURL {
                        Button("Open Home Assistant", systemImage: "safari") { openURL(serverURL) }
                    }
                }
            }
        }
        .refreshable { await store.connect() }
        .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
    }

    // MARK: Hero

    private var illustration: some View {
        // The night illustration is the dark-mode version of the hero, as in the mock-ups.
        Image(colorScheme == .dark ? "IllustrationNight" : "IllustrationDay")
            .resizable()
            .scaledToFill()
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
            .padding(.horizontal, -Theme.screenPadding)
            .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            if case .offline(let since) = store.phase {
                OfflineBanner(since: since)
                    .padding(.bottom, 10)
            } else {
                Spacer().frame(height: 9)
            }
            HeroRing(temperature: store.heroTemperature, isDimmed: store.phase != .connected)
            Spacer(minLength: 0)
        }
        .frame(height: heroSpace - Theme.sectionSpacing)
    }

    // MARK: Sections

    private var metrics: some View {
        HStack(spacing: 12) {
            MetricCard(
                symbol: "lightbulb.fill",
                title: "Lights",
                value: "\(store.lightsOn.count)",
                unit: String(localized: "on")
            )
            if let energy = store.energyToday {
                MetricCard(
                    symbol: "bolt.fill",
                    title: "Energy",
                    value: energy.numericState?.formatted(.number.precision(.fractionLength(0...1))) ?? energy.state,
                    unit: energy.unit
                )
            } else {
                MetricCard(
                    symbol: "power",
                    title: "Devices",
                    value: "\(store.devices.filter { $0.isActive && $0.kind != .sensor && $0.kind != .binarySensor }.count)",
                    unit: String(localized: "active")
                )
            }
        }
    }

    @ViewBuilder
    private var scenes: some View {
        let scenes = store.scenes
        if !scenes.isEmpty {
            VStack(spacing: 12) {
                if scenes.count > 4 {
                    SectionHeader(title: "Scenes", actionTitle: showsAllScenes ? "Show Less" : "See All") {
                        withAnimation(.smooth) { showsAllScenes.toggle() }
                    }
                } else {
                    SectionHeader(title: "Scenes")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(showsAllScenes ? scenes : Array(scenes.prefix(4))) { scene in
                        SceneTile(entity: scene)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favorites: some View {
        let favorites = store.favorites
        if !favorites.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Text("Favorites").font(.roundedTitle3)
                    Spacer()
                    NavigationLink("See All") { AllDevicesView() }
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 4)
                ForEach(favorites) { entity in
                    DeviceRow(entity: entity, showsRoom: true) { opened = OpenedDevice(id: entity.entityID) }
                }
            }
        }
    }
}

/// Shown over the hero when the server stops answering; cached data stays visible underneath.
private struct OfflineBanner: View {
    let since: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Server Unreachable")
                    .font(.roundedHeadline)
                Text("Data from \(since, format: .relative(presentation: .named)) · retrying")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 304)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Every device, grouped by type.
struct AllDevicesView: View {
    @Environment(HomeStore.self) private var store
    @State private var opened: OpenedDevice?

    var body: some View {
        let grouped = Dictionary(grouping: store.devices, by: \.kind)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(DeviceKind.allCases.filter { grouped[$0] != nil }, id: \.self) { kind in
                    Text(kind.title)
                        .font(.roundedTitle3)
                        .padding(.horizontal, 4)
                        .padding(.top, 16)
                    ForEach(grouped[kind]!.sortedByName()) { entity in
                        DeviceRow(entity: entity, showsRoom: true) { opened = OpenedDevice(id: entity.entityID) }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle("All Devices")
        .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
    }
}

#Preview("Day") {
    HomeView()
        .environment(DemoHome.store())
}

#Preview("Offline") {
    HomeView()
        .environment(DemoHome.store(phase: .offline(since: .now.addingTimeInterval(-300))))
}
