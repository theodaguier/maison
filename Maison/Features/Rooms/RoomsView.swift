import SwiftUI

struct RoomsView: View {
    @Environment(HomeStore.self) private var store
    @State private var mode: Mode = .list
    @State private var opened: OpenedDevice?
    @State private var isScanning = false
    @State private var addsRoom = false
    @State private var path: [Area] = []
    @State private var newRoom = ""
    @State private var error: String?
    @State private var showsHousekeeping = false
    @State private var namedRoom: Area?

    enum Mode: Hashable { case list, plan }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.layout.areas.isEmpty, store.currentUser?.isAdmin == false {
                    ContentUnavailableView(
                        "No Rooms Yet",
                        systemImage: "square.grid.2x2",
                        description: Text("An administrator of your home adds them from Maison.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            PillPicker(options: [(.list, "List", nil), (.plan, "Plan", nil)], selection: $mode)
                            switch mode {
                            case .list:
                                FavoritesSection(opened: $opened)
                                if let question = store.roomToConfirm {
                                    RoomKindQuestion(room: question.area, guess: question.guess) { namedRoom = question.area }
                                }
                                HousekeepingWeekCard { showsHousekeeping = true }
                                RoomList()
                                if store.currentUser?.isAdmin == true || store.isDemoHome {
                                    Button("Add a Room", systemImage: "plus") { addsRoom = true }
                                        .font(.roundedBody)
                                        .padding(.leading, 16)
                                        .padding(.vertical, 6)
                                }
                                if let error {
                                    Text(error).font(.roundedFootnote).foregroundStyle(.orange).padding(.leading, 16)
                                }
                                ScenesSection()
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
            .sheet(isPresented: $showsHousekeeping) { HousekeepingSheet() }
            .sheet(item: $namedRoom) { RoomKindPicker(room: $0) }
            .fullScreenCover(isPresented: $isScanning) { ScanScreen() }
            .alert("Add a Room", isPresented: $addsRoom) {
                TextField("Name", text: $newRoom)
                Button("Cancel", role: .cancel) { newRoom = "" }
                Button("Add") {
                    let name = newRoom
                    newRoom = ""
                    Task {
                        do {
                            try await store.createArea(named: name)
                            error = nil
                        } catch {
                            self.error = String(localized: "Couldn’t add the room. It needs an administrator account.")
                        }
                    }
                }
            } message: {
                Text("Maison adds it to your server, ready for its devices.")
            }
            .onAppear {
                // `-plan` opens the plan straight away, to check its design.
                if UserDefaults.standard.bool(forKey: "plan") { mode = .plan }
                // `-housekeeping` opens the housekeeping sheet, to check its design.
                if UserDefaults.standard.bool(forKey: "housekeeping") { showsHousekeeping = true }
                #if DEBUG
                // `-room bedroom` opens a room, to check its design.
                if let id = UserDefaults.standard.string(forKey: "room"), let room = store.layout.areas.first(where: { $0.id == id }) {
                    path = [room]
                }
                #endif
            }
        }
        .trackScreen(.rooms)
    }
}

/// Every room in one card, as in the mock-up: in orange, those where a device asks for something.
private struct RoomList: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        let areas = store.layout.areas
        VStack(spacing: 0) {
            ForEach(Array(areas.enumerated()), id: \.element.id) { index, room in
                if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 62) }
                NavigationLink(value: room) {
                    let count = store.devices(in: room).count
                    let upkeep = store.maintenance(in: room).count
                    let kind = store.roomKind(room)
                    HStack(spacing: 14) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(kind.color, in: .rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name).font(.roundedBody).foregroundStyle(.primary)
                            Text(caption(devices: count, upkeep: upkeep))
                                .font(.roundedFootnote)
                                .foregroundStyle(upkeep > 0 ? Color.orange : Color.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private func caption(devices: Int, upkeep: Int) -> String {
        let devicesText = devices == 0 ? String(localized: "No devices yet") : String(localized: "\(devices) devices")
        return upkeep == 0 ? devicesText : String(localized: "\(devicesText), \(upkeep) upkeep")
    }
}

extension Area {
    /// A symbol from the room's icon and name, for rows that don't read the store.
    var symbol: String { RoomKind.recognize(name: name, icon: icon).kind.symbol }
}

#Preview {
    RoomsView()
        .environment(DemoHome.store())
}
