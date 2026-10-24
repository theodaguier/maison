import SwiftUI

/// Onboarding until the first sign-in is done, then four tabs on the system Liquid Glass tab bar.
struct RootView: View {
    @State private var tab: AppTab = .home
    @Environment(HomeStore.self) private var store
    /// Set once on appear, so that signing in doesn't swap onboarding for the tabs before its summary.
    @State private var isOnboarding: Bool?

    var body: some View {
        Group {
            if isOnboarding ?? (store.phase == .signedOut) {
                OnboardingView {
                    withAnimation(.smooth) { isOnboarding = false }
                }
                .transition(.opacity)
            } else {
                tabs
            }
        }
        .onAppear {
            // `-onboarding` replays the setup with the demo home.
            isOnboarding = store.phase == .signedOut || ProcessInfo.processInfo.arguments.contains("-onboarding")
        }
        // A device command that didn't go through is felt even though the state simply stays as it was.
        .sensoryFeedback(.error, trigger: store.failedCommands)
        .onChange(of: store.phase) { _, phase in
            if phase == .signedOut { isOnboarding = true }
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.household.pendingInvitation != nil },
            set: { if !$0 { store.household.pendingInvitation = nil } }
        )) {
            if let metadata = store.household.pendingInvitation {
                InvitationView(metadata: metadata)
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Rooms", systemImage: "square.grid.2x2.fill", value: AppTab.rooms) {
                RoomsView()
            }
            Tab("Rules", systemImage: "clock.fill", value: AppTab.rules) {
                AutomationsView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .environment(\.selectTab, SelectTab { tab = $0 })
        #if DEBUG
        // `-tab rooms` opens a tab at launch, to check its design.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "tab") {
            case "rooms": tab = .rooms
            case "rules": tab = .rules
            case "settings": tab = .settings
            default: break
            }
        }
        #endif
    }
}

enum AppTab: Hashable {
    case home, rooms, rules, settings
}

/// Switches tab from inside a screen ("See" on the rule just created).
struct SelectTab {
    let action: (AppTab) -> Void
    func callAsFunction(_ tab: AppTab) { action(tab) }
}

extension EnvironmentValues {
    @Entry var selectTab = SelectTab { _ in }
}

#Preview {
    RootView()
        .environment(DemoHome.store())
}
