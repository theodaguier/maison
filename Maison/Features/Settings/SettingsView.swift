import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    LabeledContent("Home Assistant", value: String(localized: "Not Connected"))
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
}
