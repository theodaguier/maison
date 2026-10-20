import SwiftUI

struct HomeView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        NavigationStack {
            switch store.phase {
            case .signedOut:
                // Signed-out users see onboarding instead of the tabs.
                Color.clear
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened: OpenedDevice?
    @State private var showsAllScenes = false
    /// Today's energy use compared with the same time yesterday.
    @State private var energyTrend: Trend?
    @State private var temperatureChange: Double?
    @State private var confirmsTurnOff = false
    @State private var turnedOff = 0
    /// The day summary written on the iPhone; `nil` when Apple Intelligence isn't available.
    @State private var digest: DayDigest? = DayDigest.isAvailable && DaySummarySetting.isEnabled ? DayDigest() : nil
    @State private var readsDigest = false
    #if DEBUG
    /// `-sheet describe` opens "Describe a Rule" at launch, to check its design without switching tabs.
    @State private var describesRule = false
    #endif
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
                SummaryCard(summary: summary, digest: digest) { readsDigest = true }
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
        .navigationSubtitle(subtitle)
        .toolbar {
            if digest != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    IntelligenceButton("Your Day in Brief") { readsDigest = true }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let serverURL = store.serverURL {
                    Button("Add in Home Assistant", systemImage: "plus") {
                        openURL(serverURL.appending(path: "config/integrations/dashboard"))
                    }
                }
                Menu("More", systemImage: "ellipsis") {
                    Button("Turn Everything Off", systemImage: "power") {
                        confirmsTurnOff = true
                    }
                    .disabled(store.devicesToTurnOff.isEmpty)
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
        .task(id: store.indoorTemperatureSensors.map(\.entityID)) {
            temperatureChange = await store.temperatureChangeSinceYesterday()
        }
        .task(id: store.phase == .connected) {
            guard store.phase == .connected, let digest else { return }
            await digest.refreshIfNeeded(from: store, now: summary.sentences + summary.more)
        }
        .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
        .sheet(isPresented: $readsDigest) {
            if let digest { DaySummarySheet(digest: digest, current: summary.sentences + summary.more) }
        }
        #if DEBUG
        .sheet(isPresented: $describesRule) { DescribeRuleView() }
        // `-sheet light.lampadaire` opens a device sheet at launch, to check its design; `-sheet day` the day summary.
        .onAppear {
            guard let id = UserDefaults.standard.string(forKey: "sheet") else { return }
            switch id {
            case "day": readsDigest = digest != nil
            case "describe": describesRule = true
            default: opened = OpenedDevice(id: id)
            }
        }
        #endif
        .overlay(alignment: .bottom) {
            if let joined = store.household.joinedHouseholdName {
                Label("You joined \(joined)", systemImage: "checkmark.circle.fill")
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.12), in: .capsule)
                    .padding(.bottom, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.smooth) { store.household.joinedHouseholdName = nil }
                    }
            }
        }
        // The name is set by the iCloud share callback, outside any transaction.
        .animation(.smooth, value: store.household.joinedHouseholdName)
        .sensoryFeedback(.success, trigger: store.household.joinedHouseholdName) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: turnedOff)
        .confirmationDialog("Turn Everything Off?", isPresented: $confirmsTurnOff, titleVisibility: .visible) {
            Button("Turn Off \(store.devicesToTurnOff.count) Devices", role: .destructive) {
                Task {
                    await store.turnEverythingOff()
                    turnedOff += 1
                }
            }
        } message: {
            Text("Lights, plugs, fans and speakers. Devices set to “Never Turn Off” stay on.")
        }
    }

    private var summary: HomeSummary { store.summary(temperatureChange: temperatureChange) }

    /// "Tuesday 20 October · 15:49".
    private var subtitle: Text {
        let day = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        return Text(verbatim: "\(day.prefix(1).localizedUppercase)\(day.dropFirst()) · \(time)")
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
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
            .padding(.horizontal, -Theme.screenPadding)
            .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            if case .offline(let since) = store.phase {
                OfflineBanner(since: since)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(0.96, anchor: .bottom)))
            } else {
                Spacer().frame(height: 9)
            }
            HeroRing(temperature: store.heroTemperature, isDimmed: store.phase != .connected)
            Spacer(minLength: 0)
        }
        .animation(.smooth, value: store.phase)
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
                    unit: energy.unit,
                    trend: energyTrend
                )
                .task(id: energy.entityID) {
                    guard let change = await store.changeSinceYesterday(of: energy), change != 0 else { return }
                    energyTrend = change < 0 ? .down : .up
                }
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
                } else if let serverURL = store.serverURL {
                    SectionHeader(title: "Scenes", actionTitle: "Edit") {
                        openURL(serverURL.appending(path: "config/scene/dashboard"))
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
