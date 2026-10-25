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
                Haptics.impact()
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
    @State private var showsSources = false
    @State private var layout = HomeLayoutSetting.load()
    @State private var editsLayout = false
    @State private var editsShortcuts = false
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
    @Environment(BelongingsStore.self) private var belongings
    @State private var openedItem: Item?
    @State private var showsDocuments = false
    @State private var scansDocument = false
    #endif
    /// Height of the navigation bar area above the scroll content at rest. Kept from before the first
    /// scroll: the inset then shrinks as the large title folds away, and grows while refreshing.
    @State private var topInset: CGFloat = 0
    @State private var hasScrolled = false
    @State private var heroScroll = HeroScroll()
    /// The bar gets its opaque edge only once the illustration has scrolled away.
    @State private var isPastHero = false
    /// The clock the hero follows, a minute at a time.
    @State private var now = Date.now
    /// The painting shown for each scene, keyed by the scene's first painting, drawn again at each opening
    /// of the app. Kept per scene: the system snapshots the app in both appearances on its way out.
    @State private var shownPaintings: [String: String] = [:]

    private let heroHeight: CGFloat = 358
    /// Share of the scroll the painting follows: half, so it reads as further away than the cards.
    private let parallaxRate: CGFloat = 0.5
    /// Space between the large-title bar and the scores (design: they start at 238 pt, the bar ends at 187 pt).
    private let heroSpace: CGFloat = 51

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                hero
                ScoresCard(scores: scores, isDimmed: store.phase != .connected) { openedScore = $0 }
                ForEach(arrangedSections) { section in
                    sectionView(section)
                        .transition(.opacity)
                }
                // Housekeeping comes last: the latest chore, after what the scores have to say.
                if let late = store.allChores().first(where: { $0.isLate() }),
                   let room = store.layout.areas.first(where: { $0.id == late.roomID }) {
                    HousekeepingAttentionCard(status: late, room: room) { showsHousekeeping = true }
                        .transition(.opacity)
                }
                Button("Edit Home", systemImage: "square.and.pencil") { editsLayout = true }
                    .font(.roundedSubheadlineEmphasized)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
            .animation(.smooth, value: scores?.highlights)
            .animation(.smooth, value: layout)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
            // Exactly the screen's width: a card wider than it with real data must not let the page slide sideways.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentInsets.top }) { _, inset in
            if !hasScrolled { topInset = inset }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { [topInset] in topInset == 0 ? 0 : $0.contentOffset.y + topInset }) { _, distance in
            heroScroll.distance = distance
        }
        .onScrollPhaseChange { _, phase in
            if phase != .idle { hasScrolled = true }
        }
        .scrollEdgeEffectHidden(!isPastHero, for: .top)
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 180 }) { _, isPast in
            isPastHero = isPast
        }
        // Behind the scroll view rather than in it, so the refresh spinner stays over the painting.
        .background(alignment: .top) {
            HeroBackdrop(
                asset: shownPaintings[paintings[0]] ?? paintings[0], scroll: heroScroll,
                height: heroHeight, rate: reduceMotion ? 1 : parallaxRate
            )
            .ignoresSafeArea(edges: .top)
        }
        .background(Theme.background)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .onChange(of: paintings, initial: true) { _, paintings in
            // The hour, the weather or the appearance turned: a scene not shown yet gets its painting.
            if shownPaintings[paintings[0]] == nil { drawPainting(among: paintings) }
        }
        // Each time the app comes back; the scene phase can skip the background while the screen is not drawn.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            let current = shownPaintings[paintings[0]]
            shownPaintings = [:]
            drawPainting(among: paintings, after: current)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
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
        .navigationDestination(isPresented: $showsSources) { AllSourcesPage() }
        .sheet(isPresented: $editsLayout) { HomeLayoutEditor(layout: $layout) }
        .sheet(isPresented: $editsShortcuts) { HomeFavoritesEditor() }
        .sheet(isPresented: $readsDigest) {
            if let digest { DaySummarySheet(digest: digest, current: summary.sentences + summary.more) }
        }
        #if DEBUG
        .sheet(isPresented: $describesRule) { DescribeRuleView() }
        .sheet(item: $openedItem) { ItemSheet(itemID: $0.id) }
        .sheet(isPresented: $showsDocuments) { NavigationStack { DocumentsPage() } }
        .fullScreenCover(isPresented: $scansDocument) { DocumentScanFlow(target: nil) }
        // `-sheet light.lampadaire` opens a device sheet at launch, to check its design; `-sheet day` the day summary,
        // `-sheet item` the first object of the demo home, `-sheet documents` the documents, `-sheet scan` the scanner.
        .onAppear {
            guard let id = UserDefaults.standard.string(forKey: "sheet") else { return }
            switch id {
            case "day": readsDigest = digest != nil
            case "describe": describesRule = true
            case "item": openedItem = belongings.items.first { $0.parentItemID == nil && !belongings.consumables(of: $0).isEmpty }
            case "documents": showsDocuments = true
            case "scan": scansDocument = true
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

    /// The person's sections, a score with something to fix first.
    private var arrangedSections: [HomeSection] {
        let pressing = Set((scores?.highlights ?? []).filter(\.isPressing).map(\.score))
        return layout.arranged(withFindings: pressing)
    }

    private func open(_ destination: HomeDestination) {
        switch destination {
        case .score(let kind): openedScore = kind
        case .finding(let finding): openedFinding = finding
        case .device(let id): opened = OpenedDevice(id: id)
        case .sources: showsSources = true
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        let highlight = section.highlight(in: scores?.highlights ?? [])
        switch section {
        case .summary: SummaryCard(summary: scoredSummary, digest: digest) { readsDigest = true }
        case .shortcuts: ShortcutsRow(edit: { editsShortcuts = true }, openDevice: { opened = OpenedDevice(id: $0) })
        case .comfort: ComfortSection(scores: scores, highlight: highlight, open: open)
        case .energy: EnergySection(scores: scores, highlight: highlight, open: open)
        case .network: NetworkSection(scores: scores, highlight: highlight, open: open)
        case .weather: WeatherSection(highlight: highlight, open: open)
        case .monthCost: MonthCostSection(scores: scores, highlight: highlight, open: open)
        }
    }

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

    /// The scene outside, lit in light mode and at night in dark mode, as in the mock-ups: the title stays
    /// readable over it.
    private var paintings: [String] { scene.paintings { UIImage(named: $0) != nil } }

    /// Another painting than the one on screen, or than the one shown at the last launch.
    private func drawPainting(among paintings: [String], after current: String? = nil) {
        var generator = SystemRandomNumberGenerator()
        let key = "heroPainting.\(paintings[0])"
        let last = current ?? UserDefaults.standard.string(forKey: key)
        let next = HeroScene.next(among: paintings, after: last, using: &generator)
        shownPaintings[paintings[0]] = next
        UserDefaults.standard.set(next, forKey: key)
    }

    private var scene: HeroScene {
        var outside = store.heroScene(at: now)
        #if DEBUG
        // `-hero dusk-rain` shows one painting of the bank, whatever the hour and the weather.
        if let forced = UserDefaults.standard.string(forKey: "hero")?.split(separator: "-"), forced.count == 2,
           let period = HeroScene.Period(rawValue: String(forced[0])), let weather = HeroScene.Weather(rawValue: String(forced[1])) {
            outside = HeroScene(period: period, weather: weather, season: outside.season)
        }
        #endif
        return colorScheme == .dark ? outside.dark : outside.light
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

/// How far the home screen has scrolled from rest, negative when pulled down. Only the backdrop reads it,
/// so a scroll moves the painting without redrawing the screen.
@Observable @MainActor
private final class HeroScroll {
    var distance: CGFloat = 0
}

/// The painting behind the home screen. Scrolled up, it follows the cards at `rate`, so it reads as further
/// away; pulled down, it stretches from the top of the screen instead of leaving a gap.
private struct HeroBackdrop: View {
    let asset: String
    let scroll: HeroScroll
    let height: CGFloat
    let rate: CGFloat

    var body: some View {
        let pulled = max(-scroll.distance, 0)
        ZStack {
            // When the hour or the weather turns, the new painting fades in over the old one.
            Image(asset)
                .resizable()
                .scaledToFill()
                .id(asset)
                .transition(.opacity)
        }
        .animation(.smooth(duration: 1.2), value: asset)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .top) {
            // A veil of the screen's background under the title, so it stays readable over any painting.
            LinearGradient(colors: [Theme.background.opacity(0.55), Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: height * 0.6)
        }
        .scaleEffect((height + pulled) / height, anchor: .top)
        .offset(y: -max(scroll.distance, 0) * rate)
        .accessibilityHidden(true)
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
        .environment(BelongingsStore.demo())
}

#Preview("Offline") {
    HomeView()
        .environment(DemoHome.store(phase: .offline(since: .now.addingTimeInterval(-300))))
}
