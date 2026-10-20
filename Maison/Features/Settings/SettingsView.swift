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
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if store.serverURL != nil {
                        ProfileCard()
                        ServerCard()
                        group("Connection") {
                            SettingsRow(symbol: "network", color: .black, title: "Remote Access",
                                        value: store.serverConfig?.externalURL.flatMap { URL(string: $0)?.host() } ?? String(localized: "Not Set Up"))
                            SettingsRow(symbol: "wifi", color: .teal, title: "Local Network",
                                        value: store.serverURL?.host() ?? "")
                            SettingsRow(symbol: "person.badge.shield.checkmark.fill", color: .blue, title: "Home Assistant Permissions",
                                        value: store.currentUser?.isAdmin == true ? String(localized: "Full") : String(localized: "Standard"))
                        }
                        if !store.integrations.isEmpty {
                            group("Integrations") {
                                ForEach(integrationSummaries, id: \.domain) { item in
                                    SettingsRow(symbol: "puzzlepiece.extension.fill", color: .indigo, title: LocalizedStringKey(item.title),
                                                value: item.count > 1 ? String(localized: "\(item.count) entries") : nil)
                                }
                            }
                        }
                    }
                    group("Appearance") {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "sun.max.fill", color: .orange)
                            Picker("Theme", selection: $appearance) {
                                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .font(.roundedBody)
                            .tint(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    group("App") {
                        SettingsRow(symbol: "info.circle.fill", color: .gray, title: "Version", value: Bundle.main.versionString)
                    }
                    if store.serverURL != nil {
                        Button(role: .destructive) {
                            Task { await store.signOut() }
                        } label: {
                            Text("Sign Out")
                                .font(.roundedHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .navigationTitle("Settings")
        }
    }

    private var integrationSummaries: [(domain: String, title: String, count: Int)] {
        let grouped = Dictionary(grouping: store.integrations, by: \.domain)
        return grouped
            .map { (domain: $0.key, title: $0.value.first?.title ?? $0.key, count: $0.value.count) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.roundedTitle3)
                .padding(.leading, 4)
                .padding(.top, 10)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

private struct ProfileCard: View {
    @Environment(HomeStore.self) private var store

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
                Text(store.currentUser?.isAdmin == true ? "Administrator" : "Resident")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .cardStyle()
    }
}

/// Server health: round-trip time with a small history, and how the app reaches it.
private struct ServerCard: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Home Server", systemImage: "server.rack")
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
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
            Text("Home Assistant \(store.serverVersion ?? "") · \(store.serverURL?.host() ?? "")")
                .font(.roundedFootnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 13)
        }
        .cardStyle()
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

    private var connectionText: String {
        guard isConnected else { return String(localized: "Not connected") }
        return store.serverURL?.isLocalNetwork == true ? String(localized: "Connected locally") : String(localized: "Connected remotely")
    }
}

private struct LatencySparkline: View {
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

private struct SettingsRow: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, color: color)
            Text(title)
                .font(.roundedBody)
            Spacer()
            if let value {
                Text(value)
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsIcon: View {
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

private extension Duration {
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

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(DemoHome.store())
}
