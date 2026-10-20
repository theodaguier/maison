import ARKit
import RoomPlan
import SwiftUI

// MARK: - Plan tab

/// The "Plan" side of Rooms: the scanned plan with its devices, or an invitation to scan.
struct PlanTab: View {
    @Environment(HomeStore.self) private var store
    @Binding var opened: OpenedDevice?
    @Binding var isScanning: Bool
    @State private var placing = false

    var body: some View {
        if let plan = store.household.floorPlan {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                VStack(spacing: 10) {
                    FloorPlanView(plan: plan, onOpenDevice: { opened = OpenedDevice(id: $0) })
                    HStack(spacing: 14) {
                        legend(Circle().fill(Color.yellow).frame(width: 8, height: 8), "On")
                        legend(Circle().strokeBorder(.tertiary, lineWidth: 1).frame(width: 8, height: 8), "Off")
                        legend(Capsule().fill(Color.cyan).frame(width: 14, height: 3), "Window")
                        Spacer()
                    }
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                }
                .padding(10)
                .cardStyle()

                HStack(alignment: .top) {
                    NumberLabel(value: plan.surface.formatted(.number.precision(.fractionLength(0))), unit: "m²", size: .xLarge)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(plan.rooms.count) rooms · \(plan.devices.count) devices placed")
                            .font(.roundedSubheadlineEmphasized)
                            .foregroundStyle(.secondary)
                        Text(scannedText(plan))
                            .font(.roundedFootnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 4)

                let unplaced = unplacedDevices(plan)
                if !unplaced.isEmpty {
                    VStack(spacing: 0) {
                        Label("\(unplaced.count) devices to place", systemImage: "hand.point.up.left.fill")
                            .labelStyle(.compact)
                            .font(.roundedSubheadlineEmphasized)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        ForEach(unplaced.prefix(5)) { entity in
                            Theme.separator.frame(height: 1)
                            HStack(spacing: 12) {
                                Image(systemName: entity.symbolName)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entity.name).font(.roundedBody)
                                    if let room = store.area(of: entity)?.name {
                                        Text(room).font(.roundedFootnote).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Button("Place") { placing = true }
                                    .font(.roundedSubheadlineEmphasized)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    .cardStyle()
                }
            }
            .sheet(isPresented: $placing) { PlacementSheet(plan: plan) }
        } else {
            ScanIntro { isScanning = true }
        }
    }

    private func legend(_ mark: some View, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) { mark; Text(title) }
    }

    private func scannedText(_ plan: FloorPlan) -> String {
        let date = plan.scannedAt.formatted(.dateTime.day().month(.abbreviated))
        return plan.scannedBy.map { String(localized: "Scanned on \(date) by \($0)") } ?? String(localized: "Scanned on \(date)")
    }

    private func unplacedDevices(_ plan: FloorPlan) -> [EntityState] {
        store.devices
            .filter { ![.sensor, .binarySensor].contains($0.kind) || $0.deviceClass == "temperature" || $0.deviceClass == "window" || $0.deviceClass == "door" }
            .filter { plan.devices[$0.entityID] == nil && !store.layout.hiddenEntities.contains($0.entityID) }
            .filter { entity in
                // Only devices in a room that is on the plan.
                guard let area = store.layout.areaByEntity[entity.entityID] else { return false }
                return plan.room(forArea: area) != nil
            }
            .sortedByName()
    }
}

// MARK: - Scan intro

struct ScanIntro: View {
    let onStart: () -> Void
    private let isSupported = RoomCaptureSession.isSupported

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 30, weight: .medium))
                .frame(width: 64, height: 64)
                .background(Theme.pill, in: .rect(cornerRadius: 16, style: .continuous))
            Text("Scan Your Home")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Walk around with your iPhone: walls, doors and windows are drawn as you go. You’ll then place your devices on the plan.")
                .font(.roundedBody)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                numbered(1, "Walk along the walls of each room", "Hold the iPhone at chest height")
                numbered(2, "Tap “Next Room”", "Go through the door and keep scanning")
                numbered(3, "Tap “Done”", "The plan of your home is put together", isLast: true)
            }
            .padding(16)
            .cardStyle()
            HStack(spacing: 12) {
                Image(systemName: isSupported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isSupported ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSupported ? "LiDAR Sensor Found" : "No LiDAR Sensor").font(.roundedHeadline)
                    Text(isSupported
                         ? "The scan is computed on the iPhone; nothing is sent online."
                         : "Scanning needs an iPhone Pro. Another member of the household can scan, and the plan is shared.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .cardStyle()
            Button(action: onStart) {
                Text("Start Scanning")
                    .font(.roundedHeadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isSupported)
        }
    }

    private func numbered(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text("\(number)")
                    .font(.roundedFootnoteEmphasized)
                    .frame(width: 24, height: 24)
                    .background(Theme.pill, in: .circle)
                if !isLast {
                    Capsule().fill(Theme.gaugeTrack).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.roundedBody)
                Text(detail).font(.roundedFootnote).foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 0 : 12)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Scanning

/// Full-screen RoomPlan capture, one room after the other, then the plan to check.
struct ScanScreen: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var scan = ScanController()
    @State private var result: FloorPlan?

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(controller: scan)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    Button("Cancel", systemImage: "xmark") {
                        scan.cancel()
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("Room \(scan.roomNumber)")
                    }
                    .font(.roundedSubheadlineEmphasized)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                }
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.motion")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scan.instruction).font(.roundedSubheadlineEmphasized)
                        Text("\(scan.walls) walls · \(scan.doors) doors · \(scan.windows) windows detected")
                            .font(.roundedFootnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                Spacer()
                if let error = scan.error {
                    Text(error)
                        .font(.roundedFootnote)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }
                HStack(spacing: 12) {
                    Button {
                        scan.nextRoom()
                    } label: {
                        Text("Next Room").font(.roundedHeadline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    Button {
                        Task {
                            if let structure = await scan.finish() {
                                result = PlanBuilder.plan(from: structure, areas: store.layout.areas,
                                                          keeping: store.household.floorPlan, scannedBy: store.currentUser?.name)
                            }
                        }
                    } label: {
                        Text("Done").font(.roundedHeadline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                .disabled(scan.isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if scan.isProcessing {
                ProgressView("Putting the plan together…")
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { scan.start() }
        .sheet(item: $result) { plan in
            PlanReview(plan: plan, onRescan: {
                result = nil
                scan.restart()
            }, onSave: { dismiss() })
            .interactiveDismissDisabled()
        }
        .errorFeedback(scan.error)
    }
}

extension FloorPlan: Identifiable {
    var id: Date { scannedAt }
}

/// Drives RoomPlan: scans rooms one by one on a shared AR session, then assembles them.
@MainActor
@Observable
final class ScanController: NSObject, RoomCaptureSessionDelegate {
    private(set) var roomNumber = 1
    private(set) var walls = 0
    private(set) var doors = 0
    private(set) var windows = 0
    private(set) var instruction = String(localized: "Walk along the walls slowly")
    private(set) var isProcessing = false
    private(set) var error: String?

    @ObservationIgnored let arSession = ARSession()
    @ObservationIgnored lazy var captureView: RoomCaptureView = {
        let view = RoomCaptureView(frame: .zero, arSession: arSession)
        view.captureSession.delegate = self
        view.delegate = viewDelegate
        return view
    }()
    @ObservationIgnored private lazy var viewDelegate = CaptureViewDelegate { [weak self] data in
        Task { await self?.roomEnded(data) }
    }
    @ObservationIgnored private var rooms: [CapturedRoom] = []
    @ObservationIgnored private var finishing: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var isFinishing = false

    func start() {
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    func restart() {
        rooms = []
        roomNumber = 1
        error = nil
        start()
    }

    func nextRoom() {
        isProcessing = true
        captureView.captureSession.stop(pauseARSession: false)
    }

    func cancel() {
        captureView.captureSession.stop()
    }

    /// Stops the last room and assembles every room into one structure.
    func finish() async -> CapturedStructure? {
        isProcessing = true
        isFinishing = true
        await withCheckedContinuation { continuation in
            finishing = continuation
            captureView.captureSession.stop()
        }
        defer { isProcessing = false; isFinishing = false }
        do {
            return try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: rooms)
        } catch {
            self.error = String(localized: "The rooms couldn’t be put together. Scan again, keeping some overlap between rooms.")
            return nil
        }
    }

    private func roomEnded(_ data: CapturedRoomData) async {
        do {
            rooms.append(try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data))
        } catch {
            self.error = String(localized: "This room couldn’t be read. Walk along its walls again.")
        }
        if isFinishing {
            finishing?.resume()
            finishing = nil
        } else {
            roomNumber = rooms.count + 1
            walls = 0; doors = 0; windows = 0
            isProcessing = false
            start()
        }
    }

    // MARK: Delegates

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let counts = (room.walls.count, room.doors.count + room.openings.count, room.windows.count)
        Task { @MainActor in
            (self.walls, self.doors, self.windows) = counts
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let text = Self.text(for: instruction)
        Task { @MainActor in self.instruction = text }
    }

    nonisolated private static func text(for instruction: RoomCaptureSession.Instruction) -> String {
        switch instruction {
        case .moveCloseToWall: String(localized: "Move closer to the wall")
        case .moveAwayFromWall: String(localized: "Step back from the wall")
        case .slowDown: String(localized: "Slow down")
        case .turnOnLight: String(localized: "Turn on a light")
        case .lowTexture: String(localized: "Aim at something with more detail")
        default: String(localized: "Walk along the walls slowly")
        }
    }
}

/// Receives each finished room. Separate from the controller because RoomPlan wants its view
/// delegate to be `NSCoding`, which a main-actor class can't promise.
@objc(MaisonCaptureViewDelegate)
final class CaptureViewDelegate: NSObject, RoomCaptureViewDelegate, @unchecked Sendable {
    private let onRoom: @MainActor (CapturedRoomData) -> Void

    init(onRoom: @escaping @MainActor (CapturedRoomData) -> Void) {
        self.onRoom = onRoom
        super.init()
    }

    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        let onRoom = onRoom
        Task { @MainActor in onRoom(roomDataForProcessing) }
        // The app shows its own result: RoomPlan's preview isn't needed.
        return false
    }
}

private struct RoomCaptureRepresentable: UIViewRepresentable {
    let controller: ScanController

    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ view: RoomCaptureView, context: Context) {}
}

// MARK: - Review

/// "Your Plan": the assembled plan, its rooms and which Home Assistant area each one is.
struct PlanReview: View {
    @Environment(HomeStore.self) private var store
    @State var plan: FloorPlan
    let onRescan: () -> Void
    let onSave: () -> Void
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    FloorPlanView(plan: plan, showsDevices: false)
                        .padding(10)
                        .cardStyle()
                    HStack(alignment: .top) {
                        NumberLabel(value: plan.surface.formatted(.number.precision(.fractionLength(0))), unit: "m²", size: .xLarge)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(plan.rooms.count) rooms found").font(.roundedSubheadlineEmphasized).foregroundStyle(.secondary)
                            Text("\(plan.doors.count) doors · \(plan.windows.count) windows").font(.roundedFootnote).foregroundStyle(.tertiary)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach($plan.rooms) { $room in
                            if room.id != plan.rooms.first?.id { Theme.separator.frame(height: 1) }
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(room.name).font(.roundedBody).foregroundStyle(room.areaID == nil ? .secondary : .primary)
                                    Text("\(room.surface.formatted(.number.precision(.fractionLength(1)))) m²")
                                        .font(.roundedFootnote).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Menu {
                                    ForEach(store.layout.areas) { area in
                                        Button(area.name) {
                                            room.areaID = area.id
                                            room.name = area.name
                                        }
                                    }
                                } label: {
                                    if room.areaID != nil {
                                        Label("Linked", systemImage: "checkmark")
                                            .font(.roundedFootnoteEmphasized)
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.green.opacity(0.12), in: .capsule)
                                    } else {
                                        Text("Name").font(.roundedSubheadlineEmphasized)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                        }
                    }
                    .cardStyle()
                    if let error {
                        Text(error).font(.roundedFootnote).foregroundStyle(.orange)
                    }
                    Text("The plan and the room names are shared with the household through iCloud.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Scan Again", systemImage: "arrow.counterclockwise", action: onRescan)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .errorFeedback(error)
    }

    private func save() async {
        isSaving = true
        do {
            try await store.household.saveFloorPlan(plan)
            onSave()
        } catch {
            self.error = String(localized: "The plan is saved on this iPhone but couldn’t be shared through iCloud.")
            isSaving = false
        }
    }
}

// MARK: - Placing devices

struct PlacementSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var plan: FloorPlan
    @State private var selected: String?
    @State private var position: FloorPlan.Point?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FloorPlanView(plan: plan, placing: selected, placingPosition: position) { point in
                        position = point
                    }
                    .padding(10)
                    .cardStyle()
                    Label("Touch the plan where the device is, then drag to adjust.", systemImage: "hand.point.up.left.fill")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(candidates) { entity in
                            if entity.entityID != candidates.first?.entityID { Theme.separator.frame(height: 1) }
                            Button {
                                commitCurrent()
                                selected = entity.entityID
                                position = plan.devices[entity.entityID]
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entity.symbolName)
                                        .foregroundStyle(selected == entity.entityID ? Color.blue : Color.secondary)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entity.name).font(.roundedBody).foregroundStyle(.primary)
                                        Text(detail(for: entity)).font(.roundedFootnote)
                                            .foregroundStyle(selected == entity.entityID ? Color.blue : Color.secondary)
                                    }
                                    Spacer()
                                    if selected == entity.entityID {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(selected == entity.entityID ? Color.blue.opacity(0.06) : .clear)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardStyle()
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Place a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        commitCurrent()
                        Task {
                            try? await store.household.saveFloorPlan(plan)
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { selected = candidates.first { plan.devices[$0.entityID] == nil }?.entityID }
    }

    private var candidates: [EntityState] {
        store.devices
            .filter { ![.sensor, .binarySensor].contains($0.kind) || ["temperature", "window", "door"].contains($0.deviceClass ?? "") }
            .filter { store.layout.areaByEntity[$0.entityID].flatMap(plan.room(forArea:)) != nil }
            .sorted { (plan.devices[$0.entityID] == nil ? 0 : 1, $0.name) < (plan.devices[$1.entityID] == nil ? 0 : 1, $1.name) }
    }

    private func detail(for entity: EntityState) -> String {
        let room = store.area(of: entity)?.name ?? ""
        if entity.entityID == selected, position != nil { return String(localized: "\(room) · position chosen") }
        if plan.devices[entity.entityID] != nil { return String(localized: "\(room) · placed") }
        return room
    }

    private func commitCurrent() {
        if let selected, let position { plan.devices[selected] = position }
        position = nil
    }
}
