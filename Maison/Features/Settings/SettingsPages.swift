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
            let added = ServerSetupLog.added + (InternetCheckSetting.addedAt == nil ? [] : ["ping"])
            if !added.isEmpty {
                SettingsGroup("Set Up by Maison") {
                    ForEach(Array(added.enumerated()), id: \.offset) { index, domain in
                        if index > 0 { SettingsDivider() }
                        let title = store.integrations.first { $0.domain == domain }?.title ?? domain
                        SettingsRow(title: LocalizedStringKey(stringLiteral: title)) { IntegrationLogo(domain: domain, size: 30) }
                    }
                }
                Explanation(text: "Maison adds what your server needs by itself: devices it found on your network, and the check behind the Network score.")
            }
            if !store.integrationSummaries.isEmpty {
                SettingsGroup("Integrations") {
                    ForEach(Array(store.integrationSummaries.prefix(12).enumerated()), id: \.element.domain) { index, item in
                        if index > 0 { SettingsDivider() }
                        NavigationLink { IntegrationPage(integration: item) } label: {
                            SettingsRow(title: LocalizedStringKey(stringLiteral: item.title), detail: store.integrationDetail(item),
                                        showsChevron: true) {
                                IntegrationLogo(domain: item.domain)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            SettingsGroup {
                NavigationLink { PermissionsPage() } label: {
                    SettingsRow(symbol: "person.badge.key.fill", color: .gray, title: "Your Permissions",
                                value: store.currentUser?.isAdmin == true ? String(localized: "Full") : String(localized: "Standard"),
                                showsChevron: true)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                Button {
                    Task { await store.connect() }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .font(.roundedHeadline)
            .controlSize(.large)
        }
    }
}

// MARK: - iPhone

/// What the iPhone adds to the home, and the switch for it.
struct IPhoneSourcePage: View {
    var body: some View {
        SettingsPage(title: "iPhone") {
            SettingsGroup {
                PresenceRow()
            }
            Explanation(text: "Your iPhone tells your server when you leave or come home, for rules like “When everyone leaves”. Nothing else leaves it.")
        }
    }
}

// MARK: - Connection

struct RemoteAccessPage: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        SettingsPage(title: "Remote Access") {
            SettingsGroup {
                SettingsRow(symbol: "network", color: .black, title: "Service",
                            value: store.remoteAccessName ?? String(localized: "Not Set Up"),
                            dot: store.remoteAccessName == nil ? .orange : .green)
                if let remote = store.remoteURL {
                    SettingsDivider()
                    SettingsRow(symbol: "link", color: .gray, title: "Address", value: remote.host() ?? remote.absoluteString)
                }
            }
            if store.remoteAccessName == "Tailscale" {
                Explanation(text: "Away from home, Maison goes through Tailscale. Each member needs the Tailscale app and to accept the server’s sharing.")
            } else if store.remoteAccessName == nil {
                Explanation(text: "Your server has no remote access yet, so Maison only reaches it at home. When Home Assistant Cloud is signed in, Maison turns its remote access on by itself.")
            } else {
                Explanation(text: "At home, Maison talks to the server directly. Away, it switches to this address on its own.")
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
                Explanation(text: "These need an administrator account on your server. Everything else works with yours.")
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
            if store.integrations.contains(where: { $0.domain == integration.domain && $0.isFailing }) {
                Explanation(text: store.currentUser?.isAdmin == true
                    ? "This integration isn’t working. Maison restarts it by itself, once a day."
                    : "This integration isn’t working. Maison restarts it the next time an administrator opens the app.")
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
    private let memberID: String
    private let fallback: HouseholdMember

    @State private var error: String?
    @State private var confirmsRemove = false
    @State private var confirmsCancel = false
    @State private var confirmsLeave = false
    @State private var isEditingName = false
    @State private var isSharing = false
    @State private var shareItems: [Any] = []

    init(member: HouseholdMember) {
        memberID = member.id
        fallback = member
    }

    /// The member as the household knows them now, so a renamed person or a changed role shows at once.
    private var person: HouseholdMember {
        store.household.members.first { $0.id == memberID }?.normalized ?? fallback.normalized
    }

    var body: some View {
        let household = store.household
        let accountName = store.currentUser?.name
        let canManage = household.currentRole.canManageMembers && !person.isCurrentUser && person.role != .owner
        SettingsPage(title: person.showsAsInvitation ? "Invitation Sent" : "Household") {
            VStack(spacing: 10) {
                MemberAvatar(initials: person.initials(accountName: accountName), pending: person.showsAsInvitation, size: 72)
                if let heading = heading(for: person, accountName: accountName) {
                    Text(heading)
                        .font(.roundedTitle3)
                        .multilineTextAlignment(.center)
                }
                if person.isCurrentUser {
                    Text("You")
                        .font(.roundedFootnoteEmphasized)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.pill, in: .capsule)
                }
                RoleBadge(role: person.role)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            if person.showsAsInvitation {
                Explanation(text: "Waiting for them to accept the invitation in iCloud. Once they do, they sign in to Home Assistant with their own account.")
            } else {
                Explanation(text: person.role == .resident
                    ? "Controls devices, scenes and automations."
                    : "Can also add devices, manage members and the server.")
            }

            if person.isCurrentUser {
                VStack(spacing: 12) {
                    WideButton(title: "Edit Display Name", style: .secondary) { isEditingName = true }
                    if household.location?.isShared == true {
                        WideButton(title: "Leave Household", style: .destructive) { confirmsLeave = true }
                    }
                }
                .padding(.top, 8)
            } else if person.showsAsInvitation, canManage {
                VStack(spacing: 12) {
                    if person.invitationContact != nil {
                        WideButton(title: "Resend the Invitation", style: .secondary) {
                            Task { await resend(person) }
                        }
                    }
                    WideButton(title: "Cancel the Invitation", style: .destructive) { confirmsCancel = true }
                }
                .padding(.top, 8)
            } else if canManage {
                SettingsGroup("Role") {
                    ForEach([HouseholdRole.resident, .administrator], id: \.self) { role in
                        if role == .administrator { SettingsDivider() }
                        Button {
                            Task { await run { try await household.setRole(role, of: person) } }
                        } label: {
                            SettingsRow(symbol: role == .administrator ? "person.badge.key.fill" : "person.fill",
                                        color: role == .administrator ? .purple : .blue,
                                        title: LocalizedStringKey(stringLiteral: role.title),
                                        detail: role == .administrator
                                            ? String(localized: "Can also add devices, manage members and the server.")
                                            : String(localized: "Controls devices, scenes and automations."),
                                        value: person.role == role ? "✓" : nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                WideButton(title: "Remove from Household", style: .destructive) { confirmsRemove = true }
                    .padding(.top, 8)
            }
            if let error {
                Text(error).font(.roundedFootnote).foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $isEditingName) {
            DisplayNameSheet(name: person.resolvedName(accountName: accountName) ?? "") { newName in
                Task { await run { try await household.setDisplayName(newName, of: person) } }
            }
        }
        .sheet(isPresented: $isSharing) {
            if !shareItems.isEmpty {
                ActivitySheet(items: shareItems) { _ in isSharing = false }
                    .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog("Remove \(person.resolvedName(accountName: nil) ?? "")?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await run { try await household.remove(person) }
                    if error == nil { dismiss() }
                }
            }
        } message: {
            Text("They’ll lose access to the household’s favorites and settings. Their Home Assistant account isn’t affected.")
        }
        .confirmationDialog("Cancel the invitation?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Cancel the Invitation", role: .destructive) {
                Task {
                    await run { try await household.remove(person) }
                    if error == nil { dismiss() }
                }
            }
        } message: {
            Text("They won’t join the household unless you invite them again.")
        }
        .confirmationDialog("Leave this household?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Leave Household", role: .destructive) {
                Task {
                    await run { try await household.leave() }
                    if error == nil { dismiss() }
                }
            }
        } message: {
            Text("You’ll need a new invitation to join again. You stay signed in to Home Assistant.")
        }
        .errorFeedback(error)
    }

    /// The name in the page body. The navigation title is the section ("Household") or the invitation
    /// state, so this heading is not a second copy of that title.
    private func heading(for person: HouseholdMember, accountName: String?) -> String? {
        if person.showsAsInvitation {
            return person.resolvedName(accountName: accountName)
        }
        return person.resolvedName(accountName: accountName) ?? String(localized: "Household Member")
    }

    private func resend(_ person: HouseholdMember) async {
        guard let contact = person.invitationContact else { return }
        error = nil
        do {
            let url = try await store.household.invite(contact, as: person.role)
            let householdName = store.household.household?.name ?? String(localized: "Home")
            shareItems = [String(localized: "I’m adding you to \(householdName), you’ll see, it’s simple."), url]
            isSharing = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ action: () async throws -> Void) async {
        error = nil
        do { try await action() } catch { self.error = error.localizedDescription }
    }
}

/// The name everyone in the household sees for the current user.
private struct DisplayNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFocused: Bool
    let onSave: (String) -> Void

    init(name: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Name", text: $name)
                    .font(.roundedBody)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding(16)
                    .cardStyle(radius: Theme.rowRadius)
                Text("Shown to everyone in the household.")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
            .navigationTitle("Display Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(HouseholdMember.nonEmpty(name) == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { isFocused = true }
    }
}

/// "Owner", "Admin", "Resident" in a coloured pill.
struct RoleBadge: View {
    let role: HouseholdRole

    var body: some View {
        let color: Color = role == .resident ? .blue : .purple
        Text(role.badge)
            .font(.roundedFootnoteEmphasized)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }
}
