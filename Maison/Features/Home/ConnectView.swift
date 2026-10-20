import AuthenticationServices
import SwiftUI

/// First-run screen: lists Home Assistant servers found on the local network and signs in to one.
struct ConnectView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        let servers = store.discovery.servers
        if servers.isEmpty {
            ContentUnavailableView {
                Label("Looking for Home Assistant…", systemImage: "wifi")
            } description: {
                Text("Maison will look for your Home Assistant server on your Wi-Fi network.")
            }
        } else {
            List {
                Section {
                    ForEach(servers) { server in
                        Button {
                            signIn(to: server)
                        } label: {
                            ServerRow(server: server)
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Found on Your Network")
                } footer: {
                    Text("You’ll sign in with your Home Assistant account. Your password stays with Home Assistant.")
                }
            }
        }
    }

    private func signIn(to server: DiscoveredServer) {
        Task {
            await store.signIn(to: server.url) { url in
                try await webAuthenticationSession.authenticate(
                    using: url,
                    callbackURLScheme: HomeAssistantAuth.callbackScheme,
                    preferredBrowserSession: .ephemeral
                )
            }
        }
    }
}

private struct ServerRow: View {
    let server: DiscoveredServer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .foregroundStyle(.primary)
                Text(server.url.host() ?? server.url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let version = server.version {
                Text(version)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
