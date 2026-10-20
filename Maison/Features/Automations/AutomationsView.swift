import SwiftUI

struct AutomationsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Aucune automatisation",
                systemImage: "clock",
                description: Text("Les règles sont exécutées par votre serveur, même quand l’iPhone est éteint.")
            )
            .navigationTitle("Automatisations")
        }
    }
}

#Preview {
    AutomationsView()
}
