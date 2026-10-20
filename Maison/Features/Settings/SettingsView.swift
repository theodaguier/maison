import SwiftUI

struct SettingsView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    if let serverURL = store.serverURL {
                        LabeledContent("Home Assistant", value: serverURL.host() ?? serverURL.absoluteString)
                        Button("Sign Out", role: .destructive) {
                            Task { await store.signOut() }
                        }
                    } else {
                        LabeledContent("Home Assistant", value: String(localized: "Not Connected"))
                    }
                }
                Section("App") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
            }
            .navigationTitle("Settings")
        }
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
        .environment(HomeStore())
}
