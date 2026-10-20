import SwiftUI

struct RoomsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Pas encore de pièces",
                systemImage: "square.grid.2x2",
                description: Text("Les pièces seront importées depuis Home Assistant.")
            )
            .navigationTitle("Pièces")
        }
    }
}

#Preview {
    RoomsView()
}
