import SwiftUI

/// Onboarding until the first sign-in is done, then four tabs on the system Liquid Glass tab bar.
struct RootView: View {
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
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Rooms", systemImage: "square.grid.2x2.fill") {
                RoomsView()
            }
            Tab("Automations", systemImage: "clock.fill") {
                AutomationsView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(DemoHome.store())
}
