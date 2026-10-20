import SwiftUI

@main
struct MaisonApp: App {
    /// `-demo` fills the app with the sample home from the mock-ups, without a server.
    @State private var store = ProcessInfo.processInfo.arguments.contains("-demo") ? DemoHome.store() : HomeStore()
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                .task { await store.start() }
        }
    }
}
