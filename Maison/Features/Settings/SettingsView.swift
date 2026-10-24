import SwiftUI

enum Appearance: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct SettingsView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.setDemoMode) private var setDemoMode
    @Environment(BelongingsStore.self) private var belongings
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage(DaySummarySetting.key) private var daySummary = true
    @AppStorage(Analytics.enabledKey) private var analyticsEnabled = false
    #if DEBUG
    @State private var opensSources = UserDefaults.standard.bool(forKey: "sources") || UserDefaults.standard.string(forKey: "source") != nil
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if store.isDemoHome {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Demo Home", systemImage: "play.rectangle.fill")
                                .labelStyle(.compact)
                                .font(.roundedHeadline)
                            Text("Sample data: nothing here controls a real device. Leave the demo to connect your Home Assistant server.")
                                .font(.roundedSubheadline)
                                .foregroundStyle(.secondary)
                            WideButton(title: "Leave the Demo", style: .secondary) { setDemoMode(false) }
                        }
                        .padding(16)
                        .cardStyle()
                    }
                    if store.serverURL != nil {
                        NavigationLink { ProfilePage() } label: { ProfileCard() }
                            .buttonStyle(.plain)
                        SettingsGroup("Sources") {
                            NavigationLink { ServerPage() } label: {
                                SettingsRow(title: "Home Assistant", detail: homeAssistantDetail, showsChevron: true) {
                                    HomeAssistantTile(size: 30)
                                }
                            }
                            SettingsDivider()
                            NavigationLink { IPhoneSourcePage() } label: {
                                SettingsRow(title: "iPhone", detail: iPhoneDetail, showsChevron: true) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 30, height: 30)
                                        .background(Theme.card, in: .rect(cornerRadius: 8))
                                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1) }
                                }
                            }
                            SettingsDivider()
                            NavigationLink { AllSourcesPage() } label: {
                                HStack(spacing: 12) {
                                    SettingsIcon(symbol: "plus", color: .blue)
                                    Text("Add a Source").font(.roundedBody).foregroundStyle(.blue)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .contentShape(.rect)
                            }
                        }
                        .buttonStyle(.plain)
                        .task { await store.measureLatency() }
                    }
                    SettingsGroup("Household") {
                        HouseholdSection()
                    }
                    if store.serverURL != nil {
                        SettingsGroup("Connection") {
                            NavigationLink { RemoteAccessPage() } label: {
                                SettingsRow(symbol: "network", color: .black, title: "Remote Access",
                                            value: store.remoteAccessName ?? String(localized: "Not Set Up"),
                                            dot: store.remoteAccessName == nil ? nil : .green, showsChevron: true)
                            }
                            SettingsDivider()
                            NavigationLink { LocalNetworkPage() } label: {
                                SettingsRow(symbol: "wifi", color: .teal, title: "Local Network",
                                            value: store.serverURL?.host() ?? "", showsChevron: true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    SettingsGroup("Paperwork") {
                        NavigationLink { DocumentsPage() } label: {
                            SettingsRow(symbol: "doc.text.fill", color: .indigo, title: "Documents",
                                        value: belongings.documents.isEmpty ? nil : "\(belongings.documents.count)",
                                        showsChevron: true)
                        }
                    }
                    .buttonStyle(.plain)
                    SettingsGroup("Appearance") {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "sun.max.fill", color: .orange)
                            Text("Theme")
                                .font(.roundedBody)
                            Spacer()
                            Menu {
                                Picker("Theme", selection: $appearance) {
                                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                                }
                                .sensoryFeedback(.selection, trigger: appearance)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(appearance.title)
                                    Image(systemName: "chevron.up.chevron.down").font(.footnote)
                                }
                                .font(.roundedSubheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                            }
                            .tint(.secondary)
                        }
                        .padding(.vertical, 6)
                        SettingsDivider()
                        NavigationLink { DaySummaryPage() } label: {
                            SettingsRow(symbol: "sparkles", color: .indigo, title: "Day Summary",
                                        value: !DayDigest.isAvailable ? String(localized: "Unavailable")
                                            : daySummary ? String(localized: "setting.enabled", defaultValue: "On")
                                            : String(localized: "setting.disabled", defaultValue: "Off"),
                                        showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                    SettingsGroup("App") {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "chart.bar.fill", color: .purple)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Share Usage Data")
                                    .font(.roundedBody)
                                Text("How you use Maison. Never your home.")
                                    .font(.roundedFootnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 8)
                            Toggle("Share Usage Data", isOn: Binding(
                                get: { analyticsEnabled },
                                set: { enabled in
                                    analyticsEnabled = enabled
                                    Analytics.shared.setEnabled(enabled)
                                }
                            ))
                            .labelsHidden()
                            .tint(.green)
                        }
                        .padding(.vertical, 6)
                        SettingsDivider()
                        SettingsRow(symbol: "info.circle.fill", color: .gray, title: "Version", value: Bundle.main.versionString)
                    }
                    if store.serverURL != nil, !store.isDemoHome {
                        SignOutButton()
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .navigationTitle("Settings")
            #if DEBUG
            // `-sources YES` opens All Sources, to check its design; `-source meter` one of them.
            .navigationDestination(isPresented: $opensSources) { AllSourcesPage() }
            #endif
        }
        .trackScreen(.settings)
    }

    /// "Connected locally, 34 ms".
    private var homeAssistantDetail: String {
        guard store.phase == .connected else { return String(localized: "Not connected") }
        let local = store.serverURL?.isLocalNetwork == true
        guard let latency = store.latencies.last else {
            return local ? String(localized: "Connected locally") : String(localized: "Connected remotely")
        }
        let milliseconds = Int(latency.milliseconds)
        return local ? String(localized: "Connected locally, \(milliseconds) ms") : String(localized: "Connected remotely, \(milliseconds) ms")
    }

    /// What the iPhone gives the home.
    private var iPhoneDetail: String {
        if store.presence.isEnabled { return String(localized: "Location") }
        if store.isTrackedByHomeAssistant { return String(localized: "Location, through the Home Assistant app") }
        return String(localized: "Nothing shared")
    }
}

/// The "Day Summary" switch, on by default; the home screen reads it before writing the summary.
enum DaySummarySetting {
    static let key = "daySummaryEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

// MARK: - Building blocks

/// A titled card of rows, as on the Settings screen.
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.roundedTitle3)
                    .padding(.leading, 4)
                    .padding(.top, 10)
            }
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Theme.separator.frame(height: 1).padding(.leading, 42)
    }
}

/// Whether Maison tells Home Assistant when you leave or come home; switched off here as well as turned on.
struct PresenceRow: View {
    @Environment(HomeStore.self) private var store
    @State private var error: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: "location.fill", color: .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Location")
                    .font(.roundedBody)
                if let error {
                    Text(error)
                        .font(.roundedFootnote)
                        .foregroundStyle(.orange)
                } else if store.isTrackedByHomeAssistant, !store.presence.isEnabled {
                    Text("Home Assistant already knows when you’re home, through its own app.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            PresenceToggle(error: $error)
        }
        .padding(.vertical, 6)
        .errorFeedback(error)
    }
}

struct SettingsRow<Icon: View>: View {
    let title: LocalizedStringKey
    var detail: String?
    var value: String?
    var dot: Color?
    var showsChevron = false
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.roundedBody)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            if let value {
                Text(value)
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

extension SettingsRow where Icon == SettingsIcon {
    init(symbol: String, color: Color, title: LocalizedStringKey, detail: String? = nil, value: String? = nil,
         dot: Color? = nil, showsChevron: Bool = false) {
        self.init(title: title, detail: detail, value: value, dot: dot, showsChevron: showsChevron) {
            SettingsIcon(symbol: symbol, color: color)
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: .rect(cornerRadius: 8))
    }
}

/// The person signed in, as at the top of Settings.
struct ProfileCard: View {
    @Environment(HomeStore.self) private var store
    var showsChevron = true

    var body: some View {
        let name = store.currentUser?.name ?? ""
        HStack(spacing: 12) {
            Text(name.prefix(1).uppercased())
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(width: 46, height: 46)
                .background(Theme.pill, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? String(localized: "Home Assistant") : name)
                    .font(.roundedHeadline)
                Text(store.profileSubtitle)
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .cardStyle()
        .contentShape(.rect)
    }
}

/// Server health: round-trip time with a small history, and how the app reaches it.
struct ServerCard: View {
    @Environment(HomeStore.self) private var store
    var showsArrow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label {
                    Text("Home Server")
                } icon: {
                    HomeAssistantTile(size: 18)
                }
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
                Spacer()
                if showsArrow {
                    Image(systemName: "arrow.right").font(.roundedSubheadline).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 12)
            Theme.separator.frame(height: 1)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    NumberLabel(value: latestMilliseconds.map(String.init) ?? "–", unit: "ms")
                    Label(connectionText, systemImage: isConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .labelStyle(.compact)
                        .font(.roundedFootnoteEmphasized)
                        .foregroundStyle(isConnected ? .green : .orange)
                }
                Spacer()
                LatencySparkline(samples: store.latencies.map(\.milliseconds))
                    .frame(width: 130, height: 40)
            }
            .padding(16)
            Theme.separator.frame(height: 1)
            Text(footer)
                .font(.roundedFootnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .cardStyle()
        .contentShape(.rect)
        .task {
            while !Task.isCancelled {
                await store.measureLatency()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var isConnected: Bool { store.phase == .connected }

    private var latestMilliseconds: Int? {
        store.latencies.last.map { Int($0.milliseconds) }
    }

    private var footer: String {
        store.household.status == .ready && store.household.household != nil
            ? String(localized: "Home Assistant \(store.serverVersion ?? ""), synced with iCloud")
            : String(localized: "Home Assistant \(store.serverVersion ?? ""), \(store.serverURL?.host() ?? "")")
    }

    private var connectionText: String {
        guard isConnected else { return String(localized: "Not connected") }
        return store.serverURL?.isLocalNetwork == true ? String(localized: "Connected locally") : String(localized: "Connected remotely")
    }
}

struct LatencySparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = normalized(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.addLines(points)
                    }
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle().fill(Color.green).frame(width: 7, height: 7).position(last)
                    }
                }
            }
        }
        .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard let low = samples.min(), let high = samples.max() else { return [] }
        let span = max(high - low, 1)
        let step = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
        return samples.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height * 0.85 - (value - low) / span * size.height * 0.7)
        }
    }
}

struct SignOutButton: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.setDemoMode) private var setDemoMode
    @State private var confirms = false

    var body: some View {
        WideButton(title: store.isDemoHome ? "Leave the Demo" : "Sign Out", style: .destructive) {
            if store.isDemoHome { setDemoMode(false) } else { confirms = true }
        }
        .confirmationDialog("Sign out of Home Assistant?", isPresented: $confirms, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Haptics.impact(.medium)
                Task { await store.signOut() }
            }
        } message: {
            Text("The household, plan and favorites stay in iCloud.")
        }
    }
}

// MARK: - Derived text

extension HomeStore {
    /// "Administrator · Apple Account"
    var profileSubtitle: String {
        let rights = currentUser?.isAdmin == true ? String(localized: "Administrator") : String(localized: "Resident")
        return household.status == .ready ? String(localized: "\(rights), Apple Account") : rights
    }

    /// "Tailscale", "Nabu Casa" or the remote host; `nil` when the server has no address away from home.
    var remoteAccessName: String? {
        guard let host = remoteURL?.host(), !host.isEmpty else { return nil }
        if host.hasSuffix(".ts.net") { return "Tailscale" }
        if host.hasSuffix(".ui.nabu.casa") { return "Nabu Casa" }
        return host
    }

    /// Devices the integration provides: "2 speakers", "3 devices".
    func devices(of integration: IntegrationSummary) -> [EntityState] {
        devices.filter { layout.platformByEntity[$0.entityID] == integration.domain }.sortedByName()
    }

    func integrationDetail(_ integration: IntegrationSummary) -> String? {
        let devices = devices(of: integration)
        guard !devices.isEmpty else { return integration.count > 1 ? String(localized: "\(integration.count) entries") : nil }
        let kinds = Set(devices.map(\.kind))
        if kinds == [.mediaPlayer], devices.allSatisfy({ $0.deviceClass == "speaker" }) {
            return String(localized: "\(devices.count) speakers")
        }
        if kinds == [.light] { return String(localized: "\(devices.count) lights") }
        return String(localized: "\(devices.count) devices")
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

extension URL {
    /// Whether the host is on the local network (private IPv4 range or a `.local` name).
    var isLocalNetwork: Bool {
        guard let host = host() else { return false }
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(DemoHome.store())
        .environment(BelongingsStore.demo())
}
