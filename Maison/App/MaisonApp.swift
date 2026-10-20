import SwiftUI

@main
struct MaisonApp: App {
    @State private var store = HomeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .environment(store)
                .task { await store.start() }
        }
    }
}
