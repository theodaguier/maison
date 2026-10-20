import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Aucun serveur connecté",
                systemImage: "house",
                description: Text("Maison cherchera votre serveur Home Assistant sur le Wi-Fi.")
            )
            .navigationTitle("Maison")
        }
    }
}

#Preview {
    HomeView()
}
