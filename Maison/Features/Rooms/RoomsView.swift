import SwiftUI

struct RoomsView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.rooms.isEmpty {
                    ContentUnavailableView(
                        "No Rooms Yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Rooms will be imported from Home Assistant.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(store.rooms) { room in
                                NavigationLink(value: room) {
                                    RoomCard(room: room)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.bottom, 24)
                    }
                    .background(Theme.background)
                }
            }
            .navigationTitle("Rooms")
            .navigationDestination(for: Area.self) { RoomView(room: $0) }
        }
    }
}

private struct RoomCard: View {
    @Environment(HomeStore.self) private var store
    let room: Area

    var body: some View {
        let devices = store.devices(in: room)
        let active = devices.filter { $0.isActive && $0.kind != .sensor && $0.kind != .binarySensor }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: Self.symbol(for: room.name))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(active.isEmpty ? Color.secondary : Color.orange)
                Spacer()
                if let temperature = store.averageValue(of: "temperature", in: room) {
                    Text(EntityState.degrees(temperature))
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(room.name)
                    .font(.roundedHeadline)
                    .lineLimit(1)
                Text(active.isEmpty ? String(localized: "All off") : String(localized: "\(active.count) on"))
                    .font(.roundedFootnote)
                    .foregroundStyle(active.isEmpty ? Color.secondary : Color.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .cardStyle(radius: Theme.tileRadius)
    }

    static func symbol(for name: String) -> String {
        let name = name.lowercased()
        if ["salon", "living", "séjour"].contains(where: name.contains) { return "sofa.fill" }
        if ["chambre", "bedroom"].contains(where: name.contains) { return "bed.double.fill" }
        if ["cuisine", "kitchen"].contains(where: name.contains) { return "fork.knife" }
        if ["bain", "bath", "douche"].contains(where: name.contains) { return "shower.fill" }
        if ["bureau", "office"].contains(where: name.contains) { return "desktopcomputer" }
        if ["entrée", "entrance", "couloir", "hall"].contains(where: name.contains) { return "door.left.hand.closed" }
        if ["jardin", "garden", "terrasse", "balcon"].contains(where: name.contains) { return "leaf.fill" }
        if ["garage"].contains(where: name.contains) { return "car.fill" }
        return "square.split.bottomrightquarter.fill"
    }
}

#Preview {
    RoomsView()
        .environment(DemoHome.store())
}
