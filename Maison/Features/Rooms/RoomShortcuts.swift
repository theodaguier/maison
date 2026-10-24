import SwiftUI

/// Favourites at the top of Rooms, before the rooms themselves.
struct FavoritesSection: View {
    @Environment(HomeStore.self) private var store
    @Binding var opened: OpenedDevice?

    var body: some View {
        let favorites = store.favorites
        if !favorites.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Text("Favorites").font(.roundedTitle3)
                    Spacer()
                    NavigationLink("See All") { AllDevicesView() }
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                // Three, as in the mock-up: the rest is one tap away in See All.
                ForEach(favorites.prefix(3)) { entity in
                    DeviceRow(entity: entity, showsRoom: true) { opened = OpenedDevice(id: entity.entityID) }
                }
            }
        }
    }
}

/// The household's scenes, four at first.
struct ScenesSection: View {
    @Environment(HomeStore.self) private var store
    @State private var showsAll = false

    var body: some View {
        let scenes = store.scenes
        if !scenes.isEmpty {
            VStack(spacing: 12) {
                if scenes.count > 4 {
                    SectionHeader(title: "Scenes", actionTitle: showsAll ? "Show Less" : "See All") {
                        withAnimation(.smooth) { showsAll.toggle() }
                    }
                } else {
                    SectionHeader(title: "Scenes")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(showsAll ? scenes : Array(scenes.prefix(4))) { scene in
                        SceneTile(entity: scene)
                    }
                }
            }
        }
    }
}
