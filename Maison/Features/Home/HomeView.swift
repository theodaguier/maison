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
        .trackScreen(.home)
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened: OpenedDevice?
    @State private var scores: HomeScores?
    @State private var openedScore: ScoreKind?
    @State private var openedFinding: Finding?
    @State private var showsHousekeeping = false
    @State private var createdRule: AutomationRule?
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

    private let heroHeight: CGFloat = 358
    /// Space between the large-title bar and the scores (design: they start at 238 pt, the bar ends at 187 pt).
    private let heroSpace: CGFloat = 51

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                hero
                ScoresCard(scores: scores, isDimmed: store.phase != .connected) { openedScore = $0 }
                SummaryCard(summary: scoredSummary, digest: digest) { readsDigest = true }
                if let attention = Attention.pick(from: scores) {
                    AttentionCard(attention: attention) {
                        if let id = attention.findingID, let finding = scores?.findings.first(where: { $0.id == id }) {
                            openedFinding = finding
                        } else {
                            openedScore = attention.kind
                        }
                    }
                    .transition(.opacity)
                } else if let late = store.allChores().first(where: { $0.isLate() }),
                          let room = store.layout.areas.first(where: { $0.id == late.roomID }) {
                    // Housekeeping comes last: only when the three scores have nothing more urgent.
                    HousekeepingAttentionCard(status: late, room: room) { showsHousekeeping = true }
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: Attention.pick(from: scores))
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
            .background(alignment: .top) { illustration.offset(y: -topInset) }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentInsets.top }) { _, inset in
            topInset = inset
        }
        .scrollEdgeEffectHidden(!isPastHero, for: .top)
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 180 }) { _, isPast in
            isPastHero = isPast
        }
        .background(Theme.background)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle(store.serverConfig?.locationName ?? String(localized: "Home"))
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    if digest?.written != nil {
                        Button("Your Day in Brief", systemImage: "sparkles") { readsDigest = true }
                    }
                    Button("Turn Everything Off", systemImage: "power") {
                        confirmsTurnOff = true
                    }
                    .disabled(store.devicesToTurnOff.isEmpty)
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.connect() }
                    }
                }
            }
        }
        .refreshable {
            await store.connect()
            scores = await store.loadScores()
        }
        .task(id: store.phase == .connected) {
            // Scores move slowly: every five minutes is enough, and the history queries stay light.
            while !Task.isCancelled {
                await refreshScores()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .task(id: ScoreInputs(store: store)) {
            // A source just added brings entities, or a room: count them now rather than at the next round.
            guard scores != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            scores = await store.loadScores()
        }
        .sheet(item: $openedScore) { ScoreSheet(kind: $0, scores: scores) }
        .sheet(isPresented: $showsHousekeeping) { HousekeepingSheet() }
        .sheet(item: $openedFinding) { finding in
            NavigationStack {
                FindingView(finding: finding) { rule in
                    createdRule = rule
                    Task { scores = await store.loadScores() }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { openedFinding = nil }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) {
            if let createdRule {
                RuleCreatedBanner(rule: createdRule) { withAnimation(.smooth) { self.createdRule = nil } }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: createdRule?.id)
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
            case "comfort", "energy", "network": openedScore = ScoreKind(rawValue: id)
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

    private func refreshScores() async {
        guard store.phase == .connected || scores == nil, !store.states.isEmpty else { return }
        // The scores first: setting up the server can wait for a device, and the rings would wait with it.
        let started = ContinuousClock.now
        var loaded = await store.loadScores()
        let duration = ContinuousClock.now - started
        scores = loaded
        if await store.setUpServer() {
            loaded = await store.loadScores()
            scores = loaded
        }
        #if DEBUG
        await store.writeScoreDiagnostics(loaded, duration: duration)
        // `-sheet finding` opens the first finding once the scores are in.
        if UserDefaults.standard.string(forKey: "sheet") == "finding", openedFinding == nil { openedFinding = loaded.findings.first }
        #endif
    }

    /// The scores first; on a calm day the device sentences wait behind "more".
    private var scoredSummary: HomeSummary {
        let sentences = scores?.sentences ?? []
        guard !sentences.isEmpty else { return summary }
        return HomeSummary(
            title: summary.title,
            sentences: sentences + (summary.isCalm ? [] : summary.sentences),
            more: (summary.isCalm ? summary.sentences : []) + summary.more,
            isCalm: summary.isCalm
        )
    }

    /// "Tuesday 20 October, 15:49".
    private var subtitle: Text {
        let day = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        return Text(verbatim: "\(day.prefix(1).localizedUppercase)\(day.dropFirst()), \(time)")
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
            }
        }
        .animation(.smooth, value: store.phase)
        .frame(minHeight: heroSpace - Theme.sectionSpacing, alignment: .bottom)
    }
}

/// What the scores are computed from: entities appearing or moving to a room, not their values changing.
private struct ScoreInputs: Hashable {
    let entities: Int
    let layout: HomeLayout

    @MainActor init(store: HomeStore) {
        entities = store.states.count
        layout = store.layout
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
                Text("Data from \(since, format: .relative(presentation: .named)), retrying")
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
