import SwiftUI

struct RoomsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Rooms Yet",
                systemImage: "square.grid.2x2",
                description: Text("Rooms will be imported from Home Assistant.")
            )
            .navigationTitle("Rooms")
        }
    }
}

#Preview {
    RoomsView()
}
