import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Server Connected",
                systemImage: "house",
                description: Text("Maison will look for your Home Assistant server on your Wi-Fi network.")
            )
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}
