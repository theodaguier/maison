import SwiftUI

/// Settings → Household: the people sharing this home through iCloud, and the invite button.
struct HouseholdSection: View {
    @Environment(HomeStore.self) private var store
    @State private var isInviting = false
    @State private var memberToRemove: HouseholdMember?
    @State private var isConfirmingLeave = false
    @State private var errorMessage: String?

    var body: some View {
        let household = store.household
        Group {
            switch household.status {
            case .loading:
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "person.2.fill", color: .indigo)
                    Text("Loading Household…")
                        .font(.roundedBody)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
                .padding(.vertical, 10)
            case .unavailable:
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(symbol: "icloud.slash.fill", color: .gray, title: "iCloud Unavailable")
                    Text("Sign in to iCloud in the Settings app to share this home. Favorites stay on this iPhone until then.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(symbol: "exclamationmark.icloud.fill", color: .orange, title: "Couldn’t Load Household")
                    Text(message)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await household.reload() }
                    }
                    .font(.roundedSubheadlineEmphasized)
                    .padding(.vertical, 12)
                }
            case .ready:
                ForEach(household.members) { member in
                    MemberRow(member: member, fallbackName: store.currentUser?.name)
                        .contextMenu {
                            if household.currentRole.canManageMembers, !member.isCurrentUser, member.role != .owner {
                                Button("Remove from Household", systemImage: "person.badge.minus", role: .destructive) {
                                    memberToRemove = member
                                }
                            }
                        }
                }
                if household.canInvite {
                    Button {
                        isInviting = true
                    } label: {
                        SettingsRow(symbol: "person.badge.plus", color: .blue, title: "Invite Someone")
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if household.location?.isShared == true {
                    Button(role: .destructive) {
                        isConfirmingLeave = true
                    } label: {
                        SettingsRow(symbol: "rectangle.portrait.and.arrow.right", color: .red, title: "Leave Household")
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $isInviting) {
            InviteSheet()
        }
        .confirmationDialog(
            "Remove \(memberToRemove?.name ?? "")?",
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove", role: .destructive) {
                Task { await run { try await household.remove(member) } }
            }
        } message: { _ in
            Text("They’ll lose access to the household’s favorites and settings. Their Home Assistant account isn’t affected.")
        }
        .confirmationDialog("Leave this household?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave Household", role: .destructive) {
                Task { await run { try await household.leave() } }
            }
        } message: {
            Text("You’ll need a new invitation to join again. You stay signed in to Home Assistant.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MemberRow: View {
    let member: HouseholdMember
    /// Shown for the current user when iCloud doesn't share their name.
    let fallbackName: String?

    var body: some View {
        let name = member.name ?? (member.isCurrentUser ? fallbackName : nil)
        HStack(spacing: 12) {
            Text((name ?? "?").prefix(1).uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(Theme.pill, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? String(localized: "Invited Person"))
                    .font(.roundedBody)
                    .lineLimit(1)
                if member.isCurrentUser {
                    Text("You")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(member.isPending ? String(localized: "Invited") : member.role.title)
                .font(.roundedSubheadline)
                .foregroundStyle(member.isPending ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

extension HouseholdRole {
    var title: String {
        switch self {
        case .owner: String(localized: "Owner")
        case .administrator: String(localized: "Administrator")
        case .resident: String(localized: "Resident")
        }
    }
}

/// Picks who to invite and their role, then hands the iCloud link to the share sheet.
private struct InviteSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var contact = ""
    @State private var role: HouseholdRole = .resident
    @State private var link: URL?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var isContactFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if let link {
                        ready(link)
                    } else {
                        form
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Invite Someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(link == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var householdName: String {
        store.household.household?.name ?? String(localized: "Home")
    }

    @ViewBuilder private var form: some View {
        SectionHeader(title: "Their iCloud Account")
        TextField("Email or phone number", text: $contact)
            .font(.roundedBody)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isContactFocused)
            .padding(16)
            .cardStyle(radius: Theme.rowRadius)

        SectionHeader(title: "Role")
        PillPicker(options: [
            (value: HouseholdRole.resident, title: "Resident", symbol: "person.fill"),
            (value: HouseholdRole.administrator, title: "Administrator", symbol: "person.badge.key.fill"),
        ], selection: $role)
        Text(role == .administrator
             ? "Administrators control devices, keep their own favorites and can invite or remove people."
             : "Residents control devices and keep their own favorites.")
            .font(.roundedFootnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

        Label {
            Text("They’ll sign in to Home Assistant with their own account. Maison shares the household, never your Home Assistant password.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .labelStyle(.compact)
        .font(.roundedFootnote)
        .foregroundStyle(.secondary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: Theme.rowRadius)
        .padding(.top, 8)

        if let errorMessage {
            Text(errorMessage)
                .font(.roundedFootnote)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }

        Button {
            Task { await createInvitation() }
        } label: {
            Group {
                if isCreating {
                    ProgressView()
                } else {
                    Text("Create Invitation")
                }
            }
            .font(.roundedHeadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .disabled(contact.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
        .padding(.top, 8)
        .onAppear { isContactFocused = true }
    }

    @ViewBuilder private func ready(_ link: URL) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.top, 24)
            Text("Invitation Ready")
                .font(.roundedTitle3)
            Text("Send the link to \(contact). It only opens for their iCloud account, as \(role.title.lowercased()).")
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)

        ShareLink(
            item: link,
            subject: Text("Join \(householdName) on Maison"),
            message: Text("Join \(householdName) on Maison. You’ll sign in to Home Assistant with your own account.")
        ) {
            Label("Send Invitation", systemImage: "square.and.arrow.up")
                .font(.roundedHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
    }

    private func createInvitation() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let url = try await store.household.invite(contact, as: role)
            withAnimation(.smooth) { link = url }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ScrollView {
        HouseholdSection()
            .padding(.horizontal, 16)
            .cardStyle()
            .padding()
    }
    .background(Theme.background)
    .environment(DemoHome.store())
}
