import SwiftUI

struct AutomationsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Automations",
                systemImage: "clock",
                description: Text("Automations run on your server, even when your iPhone is off.")
            )
            .navigationTitle("Automations")
        }
    }
}

#Preview {
    AutomationsView()
}
