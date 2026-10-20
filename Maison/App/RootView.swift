import SwiftUI

/// Main navigation: four tabs on the system Liquid Glass tab bar.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Rooms", systemImage: "square.grid.2x2.fill") {
                RoomsView()
            }
            Tab("Automations", systemImage: "clock.fill") {
                AutomationsView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
}
