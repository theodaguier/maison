import AuthenticationServices
import SwiftUI

/// First-run screen: the household's server when the user joined one through iCloud, then the
/// Home Assistant servers found on the local network.
struct ConnectView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        let household = store.household.household
        let servers = store.discovery.servers.filter { $0.url != household?.serverURL }
        if servers.isEmpty && household == nil {
            ContentUnavailableView {
                Label("Looking for Home Assistant…", systemImage: "wifi")
            } description: {
                Text("Maison will look for your Home Assistant server on your Wi-Fi network.")
            }
        } else {
            List {
                if let household {
                    Section {
                        Button {
                            signIn(to: household.serverURL)
                        } label: {
                            ServerRow(name: household.name, url: household.serverURL, symbol: "house.fill")
                        }
                        .tint(.primary)
                        if let remoteURL = household.remoteURL, remoteURL != household.serverURL {
                            Button {
                                signIn(to: remoteURL)
                            } label: {
                                ServerRow(name: String(localized: "Away From Home"), url: remoteURL, symbol: "globe")
                            }
                            .tint(.primary)
                        }
                    } header: {
                        Text("Your Household")
                    } footer: {
                        if store.household.location?.isShared == true {
                            Text("You joined \(household.name). Sign in with your own Home Assistant account to control it.")
                        } else {
                            Text("Sign in again to control \(household.name).")
                        }
                    }
                }
                if !servers.isEmpty {
                    Section {
                        ForEach(servers) { server in
                            Button {
                                signIn(to: server.url)
                            } label: {
                                ServerRow(name: server.name, url: server.url, version: server.version)
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

private struct ServerRow: View {
    let name: String
    let url: URL
    var version: String?
    var symbol = "server.rack"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                Text(url.host() ?? url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let version {
                Text(version)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
