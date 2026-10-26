import SwiftUI

/// What a resident does instead of an action their account can't do: one tap leaves the request on the
/// server for an administrator.
struct AskAdministratorButton: View {
    @Environment(HomeStore.self) private var store
    let request: AdministratorRequest
    @State private var phase: Phase = .idle

    enum Phase { case idle, sending, sent, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch phase {
            case .sent:
                Label("Asked", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .sending:
                ProgressView()
            case .idle, .failed:
                Button("Ask an Administrator", systemImage: "paperplane.fill") {
                    Haptics.impact()
                    Task { await send() }
                }
                .foregroundStyle(.blue)
                if phase == .failed {
                    Text("Couldn’t send the request. Try again in a moment.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.roundedSubheadlineEmphasized)
        .buttonStyle(.plain)
        .errorFeedback(phase == .failed ? "failed" : nil)
    }

    private func send() async {
        phase = .sending
        do {
            try await store.ask(request)
            phase = .sent
        } catch {
            phase = .failed
        }
    }
}

/// A line that says what the account can't do, then the request for an administrator.
struct ResidentNote: View {
    let text: LocalizedStringKey
    let request: AdministratorRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AskAdministratorButton(request: request)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Under the location switch, when the iPhone reports its position but doesn't count for its person yet.
struct PresenceLinkNote: View {
    @Environment(HomeStore.self) private var store
    @State private var isTrying = false

    var body: some View {
        if store.presence.isEnabled, let link = store.presence.trackerLink, link != .linked {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your iPhone reports its location, but doesn’t count for you yet in “When everyone leaves”.")
                    .font(.roundedFootnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if case .needsAdministrator(let request) = link {
                    AskAdministratorButton(request: request)
                } else if isTrying {
                    ProgressView()
                } else {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task {
                            isTrying = true
                            await store.presence.link(with: store)
                            isTrying = false
                        }
                    }
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.blue)
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
