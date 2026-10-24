import SwiftUI

/// Settings → Household: the people sharing this home through iCloud, and the invite button.
struct HouseholdSection: View {
    @Environment(HomeStore.self) private var store
    @State private var isInviting = false
    @State private var memberToRemove: HouseholdMember?
    @State private var isConfirmingLeave = false
    @State private var errorMessage: String?
    @State private var sentConfirmation: String?

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
                ForEach(Array(household.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { SettingsDivider() }
                    NavigationLink { MemberPage(member: member) } label: {
                        MemberRow(member: member, fallbackName: store.currentUser?.name)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if household.currentRole.canManageMembers, !member.isCurrentUser, member.role != .owner {
                            Button("Remove from Household", systemImage: "person.badge.minus", role: .destructive) {
                                memberToRemove = member
                            }
                        }
                    }
                }
                if let sentConfirmation {
                    Label(sentConfirmation, systemImage: "checkmark.circle.fill")
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(white: 0.12), in: .capsule)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .transition(.scale(0.95).combined(with: .opacity))
                }
                if household.canInvite {
                    SettingsDivider()
                    Button {
                        isInviting = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "person.badge.plus", color: .blue)
                            Text("Invite Someone").font(.roundedBody).foregroundStyle(.blue)
                            Spacer()
                        }
                        .padding(.vertical, 10)
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
            InviteSheet { channel in
                withAnimation(.smooth) { sentConfirmation = String(localized: "Invitation sent with \(channel)") }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.smooth) { sentConfirmation = nil }
                }
            }
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
        .errorFeedback(errorMessage)
        .sensoryFeedback(.success, trigger: sentConfirmation) { _, new in new != nil }
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Initials, or a person / envelope symbol when there is no name. Never a bare "?".
struct MemberAvatar: View {
    let initials: String?
    var pending = false
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            if let initials {
                Text(initials)
                    .font(.system(size: initials.count > 1 ? size * 0.32 : size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(pending ? Color.secondary : Color.primary)
            } else {
                Image(systemName: pending ? "envelope.fill" : "person.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.pill, in: .circle)
        .accessibilityHidden(true)
    }
}

private struct MemberRow: View {
    let member: HouseholdMember
    /// Shown for the current user when iCloud doesn't share their name.
    let fallbackName: String?

    var body: some View {
        let person = member.normalized
        let name = person.resolvedName(accountName: fallbackName)
        HStack(spacing: 12) {
            MemberAvatar(initials: person.initials(accountName: fallbackName), pending: person.showsAsInvitation)
            VStack(alignment: .leading, spacing: 1) {
                Text(rowTitle(name, for: person))
                    .font(.roundedBody)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if person.isCurrentUser {
                    Text("You").font(.roundedFootnote).foregroundStyle(.tertiary)
                } else if person.showsAsInvitation {
                    Text("Waiting via iCloud")
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            RoleBadge(role: person.role)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func rowTitle(_ name: String?, for person: HouseholdMember) -> String {
        if person.showsAsInvitation {
            return name ?? String(localized: "Invitation Sent")
        }
        return name ?? String(localized: "Household Member")
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

    /// The short label in the coloured pill. The owner is not an administrator.
    var badge: String {
        switch self {
        case .owner: String(localized: "Owner")
        case .administrator: String(localized: "Admin")
        case .resident: String(localized: "Resident")
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
