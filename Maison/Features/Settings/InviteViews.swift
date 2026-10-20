import CloudKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

// MARK: - Inviting (owner side)

/// "Share the Home": who to invite, their role, then the share sheet or a code to scan.
struct InviteSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSent: (String) -> Void

    @State private var contact = ""
    @State private var role: HouseholdRole = .resident
    @State private var link: URL?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var sharing = false
    @State private var showsCode = false
    @FocusState private var isContactFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    avatars
                    Text("Share the Home")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("The person invited finds everything: rooms, plan and automations.")
                        .font(.roundedBody)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Their iCloud account").font(.roundedFootnote).foregroundStyle(.tertiary)
                        TextField("Email or phone number", text: $contact)
                            .font(.roundedBody)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isContactFocused)
                            .onChange(of: contact) { link = nil }
                    }
                    .padding(16)
                    .cardStyle(radius: Theme.rowRadius)

                    roleCard(.resident, detail: "Controls devices, scenes and automations.")
                    roleCard(.administrator, detail: "Can also add devices, manage members and the server.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Done automatically").font(.roundedFootnote).foregroundStyle(.tertiary)
                        automatic("icloud.fill", .blue, "Plan, rooms and names shared through iCloud")
                        automatic("arrow.down.app.fill", .blue, "Installing the app is part of the link")
                        automatic("lock.fill", .gray, "They sign in to Home Assistant with their own account")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(radius: Theme.rowRadius)

                    if let errorMessage {
                        Text(errorMessage).font(.roundedFootnote).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        Task { if await prepare() { sharing = true } }
                    } label: {
                        ZStack {
                            Text("Invite…").opacity(isCreating ? 0 : 1)
                            if isCreating { ProgressView().tint(.white) }
                        }
                        .font(.roundedHeadline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    Button("Show a Code to Scan") {
                        Task { if await prepare() { showsCode = true } }
                    }
                    .font(.roundedSubheadlineEmphasized)
                }
                .disabled(contact.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Theme.background)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onAppear { isContactFocused = true }
        .sheet(isPresented: $sharing) {
            if let link {
                ActivitySheet(items: [message, link]) { activity in
                    sharing = false
                    if let activity {
                        onSent(activity)
                        dismiss()
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showsCode) {
            if let link { InviteCodeSheet(link: link, role: role) }
        }
    }

    private var householdName: String {
        store.household.household?.name ?? String(localized: "Home")
    }

    private var message: String {
        String(localized: "I’m adding you to \(householdName), you’ll see, it’s simple.")
    }

    private var avatars: some View {
        HStack(spacing: -6) {
            ForEach(store.household.members.prefix(4)) { member in
                Text(String((member.name ?? "?").prefix(1)))
                    .font(.roundedHeadline)
                    .frame(width: 44, height: 44)
                    .background(Theme.pill, in: .circle)
                    .overlay { Circle().strokeBorder(Theme.background, lineWidth: 2) }
            }
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Theme.background, in: .circle)
                .overlay { Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.tertiary) }
        }
        .accessibilityHidden(true)
    }

    private func roleCard(_ value: HouseholdRole, detail: LocalizedStringKey) -> some View {
        Button {
            role = value
            link = nil
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(value.title).font(.roundedHeadline).foregroundStyle(.primary)
                    Text(detail).font(.roundedFootnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: role == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(role == value ? Color.blue : Color(.tertiaryLabel))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.rowRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.rowRadius)
                    .strokeBorder(role == value ? Color.blue : Theme.cardBorder, lineWidth: role == value ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(role == value ? .isSelected : [])
    }

    private func automatic(_ symbol: String, _ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: .rect(cornerRadius: 6))
            Text(text).font(.roundedSubheadline)
        }
    }

    /// Creates the iCloud share once per person and role.
    private func prepare() async -> Bool {
        if link != nil { return true }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let share = try await store.household.invite(contact, as: role)
            link = InviteLink.url(share: share, household: householdName, inviter: store.currentUser?.name)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// The system share sheet, reporting where the invitation went ("Messages").
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            onFinish(completed ? Self.name(of: activity) : nil)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    private static func name(of activity: UIActivity.ActivityType?) -> String {
        switch activity {
        case .message?: String(localized: "Messages")
        case .mail?: String(localized: "Mail")
        case .airDrop?: "AirDrop"
        case .copyToPasteboard?: String(localized: "copy")
        default: String(localized: "the share sheet")
        }
    }
}

/// "Have this code scanned": the invitation as a QR code, for when you're together.
struct InviteCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: URL
    let role: HouseholdRole

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                QRCode(text: link.absoluteString)
                    .frame(width: 200, height: 200)
                    .padding(18)
                    .cardStyle()
                Text("Have This Code Scanned")
                    .font(.roundedTitle3)
                Text("Handy face to face, or if the link sent by Messages doesn’t open. It only works for the iCloud account you invited.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(role.title)
                    .font(.roundedFootnoteEmphasized)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1), in: .capsule)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle("Invitation Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

/// A QR code with the app icon in the middle (the highest error correction keeps it readable).
struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .overlay {
                    AppIconTile(size: 46)
                        .padding(4)
                        .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Invitation code")
        }
    }

    private static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Joining (guest side)

/// "Théo invites you to join his home": shown before accepting an invitation.
struct InvitationView: View {
    @Environment(HomeStore.self) private var store
    let metadata: CKShare.Metadata
    @State private var isJoining = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text(initial)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .frame(width: 72, height: 72)
                        .background(Theme.pill, in: .circle)
                        .padding(.top, 60)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(role.title)
                        .font(.roundedFootnoteEmphasized)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1), in: .capsule)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("You’ll be able to").font(.roundedFootnote).foregroundStyle(.tertiary)
                        can("Control the lights, heating and shutters")
                        can("Run scenes and see automations")
                        can("Keep your own favorites")
                        if role == .administrator { can("Invite and remove people") }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .padding(.horizontal, 20)
            }
            VStack(spacing: 10) {
                Button {
                    Task {
                        isJoining = true
                        await store.household.accept(metadata)
                        store.household.pendingInvitation = nil
                    }
                } label: {
                    ZStack {
                        Text("Join the Home").opacity(isJoining ? 0 : 1)
                        if isJoining { ProgressView().tint(.white) }
                    }
                    .font(.roundedHeadline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(isJoining)
                Text("You’ll then sign in to Home Assistant with your own account.")
                    .font(.roundedFootnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button("Not Now") { store.household.pendingInvitation = nil }
                    .font(.roundedSubheadlineEmphasized)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Theme.background)
    }

    private var inviter: String? {
        metadata.ownerIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) }
    }

    private var household: String? {
        metadata.share[CKShare.SystemFieldKey.title] as? String
    }

    private var initial: String {
        String((inviter ?? household ?? "?").prefix(1)).uppercased()
    }

    private var title: String {
        if let inviter { return String(localized: "\(inviter) invites you to join their home") }
        if let household { return String(localized: "You’re invited to join “\(household)”") }
        return String(localized: "You’re invited to join a home")
    }

    private var role: HouseholdRole {
        metadata.participantRole == .administrator ? .administrator : .resident
    }

    private func can(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "checkmark")
            .labelStyle(.compact)
            .font(.roundedSubheadline)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.monochrome)
            .tint(.green)
    }
}

/// Reads an invitation from a scanned code or a pasted link, then shows it.
@MainActor
enum InvitationReader {
    static func open(_ url: URL, in store: HomeStore) async throws {
        guard let share = InviteLink.shareURL(from: url) else { throw InvitationError.notAnInvitation }
        guard CloudKitHousehold.isEntitled else { throw InvitationError.noICloud }
        store.household.pendingInvitation = try await CloudKitHousehold.shareMetadata(for: share)
    }

    enum InvitationError: LocalizedError {
        case notAnInvitation, noICloud

        var errorDescription: String? {
            switch self {
            case .notAnInvitation: String(localized: "This isn’t a Maison invitation.")
            case .noICloud: String(localized: "Sign in to iCloud to join a home.")
            }
        }
    }
}

/// Camera view that returns the first QR code it reads.
struct CodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let code) in items {
                if let value = code.payloadStringValue {
                    done = true
                    onCode(value)
                    return
                }
            }
        }
    }
}
