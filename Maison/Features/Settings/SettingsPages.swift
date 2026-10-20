import SwiftUI

/// A Settings sub-page: scrolling cards on the app background.
private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                content
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Explanation: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.roundedFootnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Profile

struct ProfilePage: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        SettingsPage(title: "Profile") {
            ProfileCard(showsChevron: false)
            SettingsGroup {
                SettingsRow(symbol: "person.crop.circle.fill", color: .blue, title: "Home Assistant Account",
                            value: store.currentUser?.name ?? "–")
                SettingsDivider()
                SettingsRow(symbol: "key.fill", color: .orange, title: "Home Assistant Permissions",
                            value: store.currentUser?.isAdmin == true ? String(localized: "Full") : String(localized: "Standard"))
                SettingsDivider()
                SettingsRow(symbol: "icloud.fill", color: .cyan, title: "iCloud",
                            value: store.household.status == .unavailable ? String(localized: "Not signed in") : String(localized: "Signed in"))
                SettingsDivider()
                SettingsRow(symbol: "person.2.fill", color: .indigo, title: "Role in the Household",
                            value: store.household.currentRole.title)
            }
            Explanation(text: "Your Home Assistant account decides what you can change on the server; your role in the household decides who you can invite.")
            SignOutButton().padding(.top, 8)
        }
    }
}

// MARK: - Server

struct ServerPage: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(title: "Home Server") {
            ServerCard()
            SettingsGroup {
                SettingsRow(symbol: "house.fill", color: .orange, title: "Name", value: store.serverConfig?.locationName ?? "–")
                SettingsDivider()
                SettingsRow(title: "Version", value: store.serverVersion ?? "–") { HomeAssistantTile(size: 30) }
                SettingsDivider()
                SettingsRow(symbol: "wifi", color: .teal, title: "Local Address", value: store.serverURL?.host() ?? "–")
                SettingsDivider()
                SettingsRow(symbol: "network", color: .black, title: "Remote Address",
                            value: store.serverConfig?.externalURL.flatMap { URL(string: $0)?.host() } ?? String(localized: "Not Set Up"))
                if let update = store.lastUpdate {
                    SettingsDivider()
                    SettingsRow(symbol: "clock.fill", color: .gray, title: "Last Update",
                                value: update.formatted(.relative(presentation: .named)))
                }
            }
            HStack(spacing: 12) {
                Button {
                    Task { await store.connect() }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                if let url = store.serverURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open", systemImage: "safari").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .font(.roundedHeadline)
            .controlSize(.large)
        }
    }
}

// MARK: - Connection

struct RemoteAccessPage: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(title: "Remote Access") {
            SettingsGroup {
                SettingsRow(symbol: "network", color: .black, title: "Service",
                            value: store.remoteAccessName ?? String(localized: "Not Set Up"),
                            dot: store.remoteAccessName == nil ? .orange : .green)
                if let external = store.serverConfig?.externalURL, !external.isEmpty {
                    SettingsDivider()
                    SettingsRow(symbol: "link", color: .gray, title: "Address", value: URL(string: external)?.host() ?? external)
                }
            }
            if store.remoteAccessName == "Tailscale" {
                Explanation(text: "Away from home, Maison goes through Tailscale. Each member needs the Tailscale app and to accept the server’s sharing.")
            } else if store.remoteAccessName == nil {
                Explanation(text: "Your server has no external address, so Maison only works at home. Set one up in Home Assistant (Settings › System › Network), for instance with Tailscale or Home Assistant Cloud.")
            } else {
                Explanation(text: "Away from home, Maison uses the external address set in Home Assistant.")
            }
            if let url = store.serverURL {
                Button {
                    openURL(url.appending(path: "config/network"))
                } label: {
                    Label("Network Settings in Home Assistant", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .font(.roundedHeadline)
            }
        }
    }
}

struct LocalNetworkPage: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        SettingsPage(title: "Local Network") {
            SettingsGroup {
                SettingsRow(symbol: "wifi", color: .teal, title: "Address", value: store.serverURL?.host() ?? "–")
                SettingsDivider()
                SettingsRow(symbol: "dot.radiowaves.left.and.right", color: .blue, title: "Port",
                            value: store.serverURL?.port.map(String.init) ?? "8123")
                SettingsDivider()
                SettingsRow(symbol: "lock.fill", color: .gray, title: "Encryption",
                            value: store.serverURL?.scheme == "https" ? "HTTPS" : String(localized: "None (local network)"))
            }
            Explanation(text: "At home, Maison talks to the server directly on the Wi-Fi, found automatically with Bonjour. Nothing goes through the internet.")
        }
    }
}

struct PermissionsPage: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        let isAdmin = store.currentUser?.isAdmin == true
        SettingsPage(title: "Home Assistant Permissions") {
            SettingsGroup {
                SettingsRow(title: "Your Account", value: isAdmin ? String(localized: "Administrator") : String(localized: "Standard user")) {
                    HomeAssistantTile(size: 30)
                }
            }
            SettingsGroup("What It Allows") {
                permission("Control devices and run scenes", allowed: true)
                SettingsDivider()
                permission("Create and edit rules", allowed: isAdmin)
                SettingsDivider()
                permission("Turn-off timers and opening alerts", allowed: isAdmin)
                SettingsDivider()
                permission("Location for “When everyone leaves”", allowed: isAdmin)
            }
            if !isAdmin {
                Explanation(text: "These need an administrator account. An administrator can change your account in Home Assistant (Settings › People).")
            }
        }
    }

    private func permission(_ title: LocalizedStringKey, allowed: Bool) -> some View {
        SettingsRow(symbol: allowed ? "checkmark" : "xmark", color: allowed ? .green : .gray, title: title)
    }
}

// MARK: - Integrations

struct IntegrationPage: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.openURL) private var openURL
    let integration: IntegrationSummary
    @State private var opened: OpenedDevice?

    var body: some View {
        let devices = store.devices(of: integration)
        SettingsPage(title: LocalizedStringKey(stringLiteral: integration.title)) {
            HStack(spacing: 14) {
                IntegrationLogo(domain: integration.domain, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: integration.title).font(.roundedTitle3)
                    if let detail = store.integrationDetail(integration) {
                        Text(detail).font(.roundedSubheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.top, 8)
            if devices.isEmpty {
                Explanation(text: "This integration doesn’t provide devices shown in Maison.")
            } else {
                VStack(spacing: 8) {
                    ForEach(devices) { entity in
                        DeviceRow(entity: entity, showsRoom: true) { opened = OpenedDevice(id: entity.entityID) }
                    }
                }
            }
            if let url = store.serverURL {
                Button {
                    openURL(url.appending(path: "config/integrations/integration/\(integration.domain)"))
                } label: {
                    Label("Open in Home Assistant", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .font(.roundedHeadline)
            }
        }
        .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
    }
}

// MARK: - Day summary

struct DaySummaryPage: View {
    @AppStorage(DaySummarySetting.key) private var isOn = true

    var body: some View {
        SettingsPage(title: "Day Summary") {
            SettingsGroup {
                Toggle(isOn: $isOn) {
                    Label {
                        Text("Day Summary").font(.roundedBody)
                    } icon: {
                        SettingsIcon(symbol: "sparkles", color: .indigo)
                    }
                    .labelStyle(.compact)
                }
                .tint(.green)
                .disabled(!DayDigest.isAvailable)
                .padding(.vertical, 8)
            }
            Explanation(text: DayDigest.isAvailable
                        ? "The home card tells how your day went, written on this iPhone by Apple Intelligence. Nothing leaves the iPhone. Takes effect next time the app opens."
                        : "Needs Apple Intelligence, turned on in the Settings app, in a supported language. Until then the home card keeps its plain sentences.")
        }
    }
}

// MARK: - Members

struct MemberPage: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let member: HouseholdMember
    @State private var error: String?
    @State private var confirmsRemove = false

    var body: some View {
        let household = store.household
        let canManage = household.currentRole.canManageMembers && !member.isCurrentUser && member.role != .owner
        SettingsPage(title: LocalizedStringKey(stringLiteral: member.name ?? String(localized: "Invitation Sent"))) {
            VStack(spacing: 10) {
                Text(member.isPending ? "?" : String((member.name ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .frame(width: 72, height: 72)
                    .background(Theme.pill, in: .circle)
                Text(member.name ?? String(localized: "Invitation Sent")).font(.roundedTitle3)
                RoleBadge(role: member.role)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            if member.isPending {
                Explanation(text: "Waiting for them to accept the invitation in iCloud. Once they do, they sign in to Home Assistant with their own account.")
            }
            if canManage {
                SettingsGroup("Role") {
                    ForEach([HouseholdRole.resident, .administrator], id: \.self) { role in
                        if role == .administrator { SettingsDivider() }
                        Button {
                            Task { await run { try await household.setRole(role, of: member) } }
                        } label: {
                            SettingsRow(symbol: role == .administrator ? "person.badge.key.fill" : "person.fill",
                                        color: role == .administrator ? .purple : .blue,
                                        title: LocalizedStringKey(stringLiteral: role.title),
                                        detail: role == .administrator
                                            ? String(localized: "Can also add devices, manage members and the server.")
                                            : String(localized: "Controls devices, scenes and automations."),
                                        value: member.role == role ? "✓" : nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                WideButton(title: member.isPending ? "Cancel the Invitation" : "Remove from Household", style: .destructive) {
                    confirmsRemove = true
                }
                .padding(.top, 8)
            }
            if let error {
                Text(error).font(.roundedFootnote).foregroundStyle(.red)
            }
        }
        .confirmationDialog("Remove \(member.name ?? "")?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await run { try await household.remove(member) }
                    if error == nil { dismiss() }
                }
            }
        } message: {
            Text("They’ll lose access to the household’s favorites and settings. Their Home Assistant account isn’t affected.")
        }
    }

    private func run(_ action: () async throws -> Void) async {
        error = nil
        do { try await action() } catch { self.error = error.localizedDescription }
    }
}

/// "Admin", "Resident" in a coloured pill.
struct RoleBadge: View {
    let role: HouseholdRole

    var body: some View {
        let color: Color = role == .resident ? .blue : .purple
        Text(role == .resident ? String(localized: "Resident") : String(localized: "Admin"))
            .font(.roundedFootnoteEmphasized)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }
}
