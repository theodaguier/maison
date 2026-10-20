import AuthenticationServices
import Network
import RoomPlan
import SwiftUI

/// First run, from the welcome screen to the ready home: welcome, search, server found,
/// Home Assistant sign-in (system web sheet), automatic setup, summary.
struct OnboardingView: View {
    enum Step: Equatable {
        case welcome, join, searching, found, preparing, ready, presence
    }

    @Environment(HomeStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @State private var step = Step.welcome
    @State private var chosenServer: ServerChoice?
    @State private var showsServerPicker = false
    @State private var error: String?

    var body: some View {
        ZStack {
            // The transition sits on the Group so each step gets it; on the ZStack it never applied.
            Group {
                switch step {
                case .welcome:
                    WelcomeStep(onStart: goToSearch, onJoin: { step = .join })
                case .join:
                    JoinStep(onSetUp: goToSearch, onBack: { step = .welcome })
                case .searching:
                    SearchingStep { showsServerPicker = true }
                case .found:
                    if let server = chosenServer ?? candidates.first {
                        ServerFoundStep(
                            server: server,
                            joinedHousehold: store.household.location?.isShared == true ? store.household.household?.name : nil,
                            onSignIn: { signIn(to: server.url) },
                            onPickAnother: { showsServerPicker = true }
                        )
                    }
                case .preparing:
                    PreparingStep { step = .ready }
                case .ready:
                    ReadyStep(onFinish: { step = .presence })
                case .presence:
                    PresenceStep(onFinish: onFinish)
                }
            }
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
        }
        .animation(.smooth, value: step)
        .background(Theme.background)
        .onAppear(perform: resume)
        .onChange(of: store.discovery.servers) { _, servers in
            guard step == .searching, !servers.isEmpty else { return }
            Task {
                // Let the radar run a moment so the result doesn't flash by.
                try? await Task.sleep(for: .seconds(1))
                if step == .searching { step = .found }
            }
        }
        .onChange(of: store.household.household) { _, household in
            // Joined a household: its server is the one to sign in to.
            if household != nil, [.welcome, .join, .searching].contains(step) {
                store.discovery.start()
                step = .found
            }
        }
        .onChange(of: candidates) { _, candidates in
            if step == .found, chosenServer == nil, candidates.isEmpty { step = .searching }
        }
        .onChange(of: store.phase) { _, phase in
            switch phase {
            case .connecting, .connected:
                if step != .ready { step = .preparing }
            case .failed(let message):
                error = message
                step = .found
            default:
                break
            }
        }
        .sheet(isPresented: $showsServerPicker) {
            ServerPicker(candidates: candidates) { server in
                chosenServer = server
                step = .found
            }
        }
        .alert("Couldn’t Connect", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .errorFeedback(error)
        // The server found and the home ready are the two moments worth celebrating.
        .sensoryFeedback(trigger: step) { _, new in new == .found || new == .ready ? .success : nil }
    }

    /// The household's server first (when this iPhone joined one through iCloud), then those found on the Wi-Fi.
    private var candidates: [ServerChoice] {
        var choices: [ServerChoice] = []
        if let household = store.household.household {
            choices.append(ServerChoice(name: household.name, url: household.serverURL, remoteURL: household.remoteURL, isOnNetwork: false))
        }
        for server in store.discovery.servers where !choices.contains(where: { $0.url == server.url }) {
            choices.append(ServerChoice(name: server.name, url: server.url, remoteURL: server.externalURL, isOnNetwork: true))
        }
        return choices
    }

    private func resume() {
        switch store.phase {
        case .connecting, .connected:
            step = .preparing
        default:
            // Signing in again, or joining a household: the server is already known.
            if store.household.household != nil {
                store.discovery.start()
                step = .found
            }
        }
    }

    private func goToSearch() {
        store.discovery.start()
        step = candidates.isEmpty ? .searching : .found
    }

    private func signIn(to server: URL) {
        Task {
            await store.signIn(to: server) { url in
                try await webAuthenticationSession.authenticate(
                    using: url,
                    callbackURLScheme: HomeAssistantAuth.callbackScheme,
                    preferredBrowserSession: .ephemeral
                )
            }
        }
    }
}

struct ServerChoice: Hashable, Identifiable {
    let name: String
    let url: URL
    var remoteURL: URL?
    /// Announced on the Wi-Fi, rather than remembered from the household.
    var isOnNetwork: Bool

    var id: URL { url }
}

// MARK: - Layout

/// Content at the top, scrolling if it has to, and the actions pinned at the bottom.
private struct OnboardingPage<Content: View, Actions: View>: View {
    var top: CGFloat = 48
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, top)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 14) {
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

private struct PrimaryButton: View {
    let title: LocalizedStringKey
    var isBusy = false
    let action: () -> Void

    var body: some View {
        WideButton(title: title, isBusy: isBusy, action: action)
    }
}

private struct LinkButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.roundedSubheadlineEmphasized)
            .tint(.accentColor)
    }
}

private extension Font {
    static let onboardingTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let onboardingHeading = Font.system(size: 22, weight: .bold, design: .rounded)
}

// MARK: - 1 · Welcome

private struct WelcomeStep: View {
    @Environment(\.setDemoMode) private var setDemoMode
    let onStart: () -> Void
    let onJoin: () -> Void

    @State private var hasICloud: Bool?
    @State private var hasWiFi: Bool?

    var body: some View {
        OnboardingPage(top: 88) {
            AppIconTile(size: 76)
            Text("Welcome to Maison")
                .font(.onboardingTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 14)
            Text("Your Home Assistant, as simple as the Home app. We take care of almost everything.")
                .font(.roundedBody)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            VStack(spacing: 0) {
                StepRow(
                    title: String(localized: "Apple Account"),
                    detail: hasICloud.map { $0 ? String(localized: "Signed in to iCloud") : String(localized: "Not signed in to iCloud: household sharing will be off") }
                        ?? String(localized: "Checking…"),
                    status: hasICloud.map { $0 ? .done : .warning } ?? .inProgress
                )
                StepRow(
                    title: String(localized: "Network"),
                    detail: hasWiFi.map { $0 ? String(localized: "Connected to Wi-Fi") : String(localized: "No Wi-Fi: your server is found on your home network") }
                        ?? String(localized: "Checking…"),
                    status: hasWiFi.map { $0 ? .done : .warning } ?? .inProgress
                )
                StepRow(
                    title: String(localized: "Compatible iPhone"),
                    detail: RoomCaptureSession.isSupported
                        ? String(localized: "LiDAR sensor available to scan the plan")
                        : String(localized: "No LiDAR sensor: another member can scan the plan"),
                    status: RoomCaptureSession.isSupported ? .done : .warning,
                    isLast: true
                )
            }
            .padding(17)
            .cardStyle()
            .padding(.top, 14)
            .animation(.smooth, value: hasICloud)
            .animation(.smooth, value: hasWiFi)
        } actions: {
            PrimaryButton(title: "Get Started", action: onStart)
            HStack(spacing: 20) {
                LinkButton(title: "I Received an Invitation", action: onJoin)
                LinkButton(title: "Try a Demo Home") { setDemoMode(true) }
            }
        }
        .task {
            async let iCloud = CloudKitHousehold.isAccountAvailable()
            async let wiFi = Self.isOnWiFi()
            (hasICloud, hasWiFi) = await (iCloud, wiFi)
        }
    }

    private static func isOnWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            }
            monitor.start(queue: .global(qos: .userInitiated))
        }
    }
}

// MARK: - Joining a home

/// First launch for someone invited who opened the app themselves: join (scan the code or paste
/// the link received), or set up their own home.
private struct JoinStep: View {
    @Environment(HomeStore.self) private var store
    let onSetUp: () -> Void
    let onBack: () -> Void

    @State private var joins = true
    @State private var scanning = false
    @State private var error: String?

    var body: some View {
        OnboardingPage(top: 60) {
            AppIconTile(size: 56)
            Text("Welcome to Maison")
                .font(.onboardingTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 14)
            Text("Were you invited to join a home, or are you setting up yours?")
                .font(.roundedBody)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            VStack(spacing: 12) {
                choice(true, symbol: "person.2.fill", title: "Join a Home",
                       detail: "Tap the link received in Messages again, or scan the code shown on the iPhone of the person who invited you.")
                choice(false, symbol: "house.fill", title: "Set Up My Home",
                       detail: "You have a Home Assistant server at home.")
            }
            .padding(.top, 16)
            if let error {
                Text(error).font(.roundedFootnote).foregroundStyle(.orange).padding(.top, 10)
            }
        } actions: {
            if joins {
                PrimaryButton(title: "Scan a Code") {
                    if CodeScanner.isAvailable { scanning = true } else { error = String(localized: "The camera isn’t available. Paste the link instead.") }
                }
                LinkButton(title: "Paste the Link") {
                    guard let text = UIPasteboard.general.string, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        error = String(localized: "Copy the invitation link first, then try again.")
                        return
                    }
                    Task { await open(url) }
                }
            } else {
                PrimaryButton(title: "Continue", action: onSetUp)
                LinkButton(title: "Back", action: onBack)
            }
        }
        .sheet(isPresented: $scanning) {
            CodeScanner { code in
                scanning = false
                if let url = URL(string: code) { Task { await open(url) } }
            }
            .ignoresSafeArea()
        }
        .errorFeedback(error)
    }

    private func open(_ url: URL) async {
        error = nil
        do {
            try await InvitationReader.open(url, in: store)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func choice(_ value: Bool, symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        Button {
            withAnimation(.smooth) { joins = value }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol)
                    .labelStyle(.compact)
                    .font(.roundedHeadline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.rowRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.rowRadius)
                    .strokeBorder(joins == value ? Color.blue : Theme.cardBorder, lineWidth: joins == value ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(joins == value ? .isSelected : [])
    }
}

// MARK: - 2 · Searching

private struct SearchingStep: View {
    @Environment(\.setDemoMode) private var setDemoMode
    let onEnterAddress: () -> Void
    @State private var isTakingLong = false

    var body: some View {
        OnboardingPage(top: 68) {
            VStack(spacing: 0) {
                SignalRings(isSearching: true) {
                    AppIconTile(size: 84)
                }
                Text("Looking for your server…")
                    .font(.onboardingHeading)
                    .padding(.top, 16)
                Text("Maison is looking for Home Assistant on your Wi-Fi.")
                    .font(.roundedBody)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        } actions: {
            if isTakingLong {
                Text("Make sure this iPhone is on the same Wi-Fi as Home Assistant, and that Maison may use the local network in Settings.")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 20) {
                    LinkButton(title: "Enter the Address", action: onEnterAddress)
                    LinkButton(title: "Try a Demo Home") { setDemoMode(true) }
                }
            }
        }
        .animation(.smooth, value: isTakingLong)
        .task {
            try? await Task.sleep(for: .seconds(8))
            isTakingLong = true
        }
    }
}

// MARK: - 3 · Server found

private struct ServerFoundStep: View {
    @Environment(HomeStore.self) private var store
    let server: ServerChoice
    let joinedHousehold: String?
    let onSignIn: () -> Void
    let onPickAnother: () -> Void

    var body: some View {
        OnboardingPage {
            SignalRings {
                AppIconTile(size: 84)
                    .overlay(alignment: .topTrailing) {
                        HomeAssistantTile(size: 48, border: 3)
                            .offset(x: 43, y: -34)
                    }
            }
            .frame(maxWidth: .infinity)
            Text("Server Found")
                .font(.onboardingTitle)
                .padding(.top, 14)
            if let joinedHousehold {
                Text("You joined \(joinedHousehold). Sign in with your own Home Assistant account to control it.")
                    .font(.roundedBody)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            VStack(spacing: 0) {
                ServerLine(title: server.name, detail: server.url.host() ?? server.url.absoluteString,
                           trailing: server.isOnNetwork ? String(localized: "Wi-Fi") : nil) {
                    HomeAssistantTile(size: 40)
                }
                if let remote = server.remoteURL {
                    Theme.separator.frame(height: 1).padding(.leading, 68)
                    ServerLine(title: String(localized: "Remote Access"), detail: remote.host() ?? remote.absoluteString,
                               trailing: String(localized: "Set Up")) {
                        Image(systemName: "network")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color(white: 0.14), in: .rect(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .cardStyle()
            .padding(.top, 14)
        } actions: {
            PrimaryButton(title: "Sign In", isBusy: store.phase == .connecting, action: onSignIn)
            LinkButton(title: "Not the right server?", action: onPickAnother)
        }
    }
}

private struct ServerLine<Icon: View>: View {
    let title: String
    let detail: String
    var trailing: String?
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.roundedHeadline)
                Text(detail).font(.roundedSubheadline).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.roundedSubheadline).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// "Not the right server?": every server found, plus an address typed by hand.
private struct ServerPicker: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [ServerChoice]
    let onPick: (ServerChoice) -> Void
    @State private var address = ""

    var body: some View {
        NavigationStack {
            List {
                if !candidates.isEmpty {
                    Section("Found on Your Network") {
                        ForEach(candidates) { server in
                            Button {
                                pick(server)
                            } label: {
                                HStack(spacing: 12) {
                                    HomeAssistantTile(size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(server.name).foregroundStyle(.primary)
                                        Text(server.url.host() ?? server.url.absoluteString)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
                Section {
                    TextField("homeassistant.local:8123", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(useAddress)
                    Button("Use This Address", action: useAddress)
                        .disabled(typedURL == nil)
                } header: {
                    Text("Address")
                } footer: {
                    Text("The address you use to open Home Assistant in a browser at home.")
                }
            }
            .navigationTitle("Choose a Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "192.168.1.10:8123" or a full URL; Home Assistant's port when none is given.
    private var typedURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: withScheme), let host = components.host, !host.isEmpty else { return nil }
        if components.port == nil, components.scheme == "http" { components.port = 8123 }
        components.path = ""
        return components.url
    }

    private func useAddress() {
        guard let url = typedURL else { return }
        pick(ServerChoice(name: url.host() ?? "Home Assistant", url: url, isOnNetwork: false))
    }

    private func pick(_ server: ServerChoice) {
        onPick(server)
        dismiss()
    }
}

// MARK: - 5 · Preparing

private struct PreparingStep: View {
    @Environment(HomeStore.self) private var store
    let onDone: () -> Void

    /// Steps shown as done so far; each waits for its data, and for the previous one to be read.
    @State private var revealed = 0

    var body: some View {
        let steps = setupSteps
        let progress = Double(revealed) / Double(steps.count)
        OnboardingPage {
            NumberLabel(value: "\(Int(progress * 100))", unit: "%", size: .xLarge)
                .animation(.smooth, value: revealed)
            Text("Setting Up Your Home")
                .font(.onboardingHeading)
                .padding(.top, 10)
            Text("Everything happens on its own. You can change it all later.")
                .font(.roundedBody)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Capsule()
                .fill(Theme.gaugeTrack)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(6, proxy.size.width * progress))
                    }
                }
                .animation(.smooth, value: revealed)
                .padding(.top, 10)
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRow(
                        title: step.title,
                        detail: step.detail,
                        detailIsAccent: step.detailIsAccent,
                        status: index < revealed ? step.doneStatus : index == revealed ? .inProgress : .upcoming,
                        isLast: index == steps.count - 1
                    )
                }
            }
            .animation(.smooth, value: revealed)
            .padding(17)
            .cardStyle()
            .padding(.top, 10)
            let integrations = store.integrationSummaries
            if !integrations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Detected Integrations")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(integrations.count)")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.roundedSubheadlineEmphasized)
                    HStack(spacing: 10) {
                        ForEach(integrations.prefix(7), id: \.domain) { IntegrationLogo(domain: $0.domain, size: 36) }
                    }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)
                .cardStyle()
                .padding(.top, 10)
                .transition(.opacity)
            }
        } actions: {
            EmptyView()
        }
        .task {
            var waited = Duration.zero
            while revealed < setupSteps.count {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
                waited += .milliseconds(450)
                // Sharing waits on iCloud, which can be slow; never hold the setup on it.
                if setupSteps[revealed].isReady || waited > .seconds(6) {
                    revealed += 1
                    waited = .zero
                }
            }
            try? await Task.sleep(for: .milliseconds(700))
            onDone()
        }
    }

    private struct SetupStep {
        let title: String
        var detail: String?
        var detailIsAccent = false
        let isReady: Bool
        var doneStatus = StepStatus.done
    }

    private var setupSteps: [SetupStep] {
        let isConnected = store.phase == .connected
        let rooms = store.layout.areas
        let remote = store.serverConfig?.externalURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let sharing = store.household.status
        return [
            SetupStep(
                title: String(localized: "Server Connection"),
                detail: store.serverURL.flatMap { $0.host() }.map { String(localized: "Home Assistant · \($0)") },
                isReady: isConnected
            ),
            SetupStep(
                title: isConnected ? String(localized: "\(rooms.count) rooms imported") : String(localized: "Rooms"),
                detail: isConnected && !rooms.isEmpty ? rooms.map(\.name).formatted(.list(type: .and, width: .narrow)) : nil,
                isReady: isConnected
            ),
            SetupStep(
                title: isConnected ? String(localized: "\(store.devices.count) devices recognized") : String(localized: "Devices"),
                detail: isConnected && store.technicalEntityCount > 0
                    ? String(localized: "\(store.technicalEntityCount) technical items hidden") : nil,
                isReady: isConnected
            ),
            SetupStep(
                title: String(localized: "Choosing Favorites"),
                detail: String(localized: "One device of each type, to change anytime"),
                detailIsAccent: true,
                isReady: isConnected
            ),
            SetupStep(
                title: String(localized: "Remote Access"),
                detail: store.serverConfig == nil ? nil : remote?.host() ?? String(localized: "Not set up in Home Assistant"),
                isReady: store.serverConfig != nil
            ),
            SetupStep(
                title: String(localized: "Sharing With the Household"),
                detail: sharing == .unavailable
                    ? String(localized: "iCloud isn’t available on this iPhone")
                    : String(localized: "Layout and settings synced with iCloud"),
                isReady: sharing != .loading,
                doneStatus: sharing == .unavailable ? .warning : .done
            ),
        ]
    }
}

// MARK: - 6 · Ready

private struct ReadyStep: View {
    @Environment(HomeStore.self) private var store
    let onFinish: () -> Void
    @State private var opened: OpenedDevice?
    @State private var editsFavorites = false

    var body: some View {
        OnboardingPage {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.green, in: .circle)
                .accessibilityHidden(true)
            Text("Your Home Is Ready")
                .font(.onboardingTitle)
                .padding(.top, 14)
            HStack(spacing: 12) {
                let rooms = store.layout.areas.count, devices = store.devices.count, automations = store.automations.count
                CountTile(count: rooms, label: rooms == 1 ? String(localized: "room") : String(localized: "rooms"))
                CountTile(count: devices, label: devices == 1 ? String(localized: "device") : String(localized: "devices"))
                CountTile(count: automations, label: automations == 1 ? String(localized: "automation") : String(localized: "automations"))
            }
            .padding(.top, 14)
            let integrations = store.integrationSummaries
            if !integrations.isEmpty {
                HStack(spacing: 12) {
                    HStack(spacing: -6) {
                        ForEach(integrations.prefix(4), id: \.domain) { item in
                            IntegrationLogo(domain: item.domain, size: 22)
                                .frame(width: 30, height: 30)
                                .background(Theme.card, in: .rect(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                                }
                        }
                    }
                    Text("\(integrations.count) integrations linked to your devices")
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 12)
                .cardStyle()
                .padding(.top, 14)
            }
            let favorites = Array(store.favorites.prefix(3))
            if !favorites.isEmpty {
                Text(store.favoriteIDs.isEmpty ? "Suggested Favorites" : "Favorites")
                    .font(.roundedTitle3)
                    .padding(.leading, 4)
                    .padding(.top, 18)
                VStack(spacing: 8) {
                    ForEach(favorites) { entity in
                        DeviceRow(entity: entity, showsRoom: true) { opened = OpenedDevice(id: entity.entityID) }
                    }
                }
                .padding(.top, 10)
            }
        } actions: {
            PrimaryButton(title: "Continue", action: onFinish)
            LinkButton(title: "Edit Favorites") { editsFavorites = true }
        }
        .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
        .sheet(isPresented: $editsFavorites) { FavoritesEditor() }
    }
}

// MARK: - 7 · Presence

/// "One last thing": the position, so the home knows when everyone has left.
private struct PresenceStep: View {
    @Environment(HomeStore.self) private var store
    let onFinish: () -> Void
    @State private var presence = PresenceReporter.shared
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        OnboardingPage {
            Text("One Last Thing")
                .font(.onboardingTitle)
            Text("So the home reacts when you leave or come back.")
                .font(.roundedBody)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.blue, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location").font(.roundedHeadline)
                    Text(store.isTrackedByHomeAssistant
                         ? String(localized: "Home Assistant already knows when you’re home, through its own app.")
                         : String(localized: "For “When everyone leaves”. Shared only with your server."))
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !store.isTrackedByHomeAssistant {
                    if isWorking {
                        ProgressView()
                    } else {
                        Toggle("Location", isOn: Binding(get: { presence.isEnabled }, set: { on in Task { await toggle(on) } }))
                            .labelsHidden()
                            .tint(.green)
                    }
                }
            }
            .padding(16)
            .cardStyle()
            .padding(.top, 14)
            if let error {
                Text(error).font(.roundedFootnote).foregroundStyle(.orange).padding(.top, 10)
            }
        } actions: {
            PrimaryButton(title: "Continue", action: onFinish)
            Text("iOS will ask you to confirm.")
                .font(.roundedFootnote)
                .foregroundStyle(.tertiary)
        }
        .errorFeedback(error)
    }

    private func toggle(_ on: Bool) async {
        error = nil
        guard on else { presence.disable(); return }
        isWorking = true
        do {
            try await presence.enable(with: store)
        } catch {
            self.error = error.localizedDescription
        }
        isWorking = false
    }
}

private struct CountTile: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(count)")
                .font(NumberSize.medium.value)
                .monospacedDigit()
            Text(label)
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// Every device by room, with a checkmark on favourites.
struct FavoritesEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.rooms) { room in
                    section(room.name, devices: store.devices(in: room))
                }
                let elsewhere = store.devices.filter { store.area(of: $0) == nil }.sortedByName()
                if !elsewhere.isEmpty {
                    section(String(localized: "No Room"), devices: elsewhere)
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .onAppear {
            // Start from the suggestions so unticking one doesn't wipe the others.
            if store.favoriteIDs.isEmpty {
                store.favorites.forEach(store.toggleFavorite)
            }
        }
    }

    private func section(_ title: String, devices: [EntityState]) -> some View {
        Section(title) {
            ForEach(devices) { entity in
                Button {
                    store.toggleFavorite(entity)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entity.symbolName)
                            .foregroundStyle(entity.accent)
                            .frame(width: 26)
                        Text(entity.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if store.isFavorite(entity) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }
}
