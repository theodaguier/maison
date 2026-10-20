import SwiftUI

/// Navigation principale : quatre onglets, tab bar Liquid Glass du système.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Maison", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Pièces", systemImage: "square.grid.2x2.fill") {
                RoomsView()
            }
            Tab("Automatisation", systemImage: "clock.fill") {
                AutomationsView()
            }
            Tab("Réglages", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
}
