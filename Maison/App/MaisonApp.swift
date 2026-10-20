import SwiftUI

@main
struct MaisonApp: App {
    /// `-demo`, or "Try a Demo Home" in onboarding, fills the app with the sample home of the mock-ups.
    @State private var store = DemoMode.isOn ? DemoHome.store() : HomeStore()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                // A new store starts its screens from scratch.
                .id(ObjectIdentifier(store))
                .fontDesign(.rounded)
                .environment(store)
                .environment(\.setDemoMode) { isOn in
                    DemoMode.isOn = isOn
                    store = isOn ? DemoHome.store() : HomeStore()
                    Task { await store.start() }
                }
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    InvitationInbox.deliver { [store] metadata in
                        store.household.pendingInvitation = metadata
                    }
                    await store.start()
                }
        }
    }
}

/// Whether the app shows the sample home instead of a real server; remembered until the person leaves it.
enum DemoMode {
    private static let key = "demoMode"

    static var isOn: Bool {
        get { ProcessInfo.processInfo.arguments.contains("-demo") || UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

extension EnvironmentValues {
    /// Switches between the sample home and the real one.
    @Entry var setDemoMode: (Bool) -> Void = { _ in }
}
