import SwiftUI

struct RoomsView: View {
    @Environment(HomeStore.self) private var store
    @State private var mode: Mode = .list
    @State private var opened: OpenedDevice?
    @State private var isScanning = false

    enum Mode: Hashable { case list, plan }

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
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            PillPicker(options: [(.list, "List", nil), (.plan, "Plan", nil)], selection: $mode)
                            switch mode {
                            case .list:
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                    ForEach(store.rooms) { room in
                                        NavigationLink(value: room) {
                                            RoomCard(room: room)
                                        }
                                        .buttonStyle(.pressable)
                                    }
                                }
                            case .plan:
                                PlanTab(opened: $opened, isScanning: $isScanning)
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
            .toolbar {
                if mode == .plan, store.household.floorPlan != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Scan Again", systemImage: "viewfinder") { isScanning = true }
                    }
                }
            }
            .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
            .fullScreenCover(isPresented: $isScanning) { ScanScreen() }
            .onAppear {
                // `-plan` opens the plan straight away, to check its design.
                if UserDefaults.standard.bool(forKey: "plan") { mode = .plan }
            }
        }
        .trackScreen(.rooms)
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
                    .contentTransition(.numericText())
            }
        }
        .animation(.smooth, value: active.count)
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
