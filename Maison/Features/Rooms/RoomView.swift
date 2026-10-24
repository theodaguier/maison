import SwiftUI

/// One room: its key measurements as ring cards, then its devices by category.
struct RoomView: View {
    /// Upkeep marked done here, hidden right away.
    @State private var done: Set<String> = []
    /// The chore just marked done, for the banner and its Undo.
    @State private var choreDone: ChoreDone?
    @Environment(HomeStore.self) private var store
    let room: Area
    @State private var opened: OpenedDevice?
    @State private var topInset: CGFloat = 0
    /// The bar gets its opaque edge only once the illustration has scrolled away.
    @State private var isPastHero = false

    private let heroHeight: CGFloat = 380
    /// Space between the large-title bar and the first card (design: cards start at 330 pt, bar ends at 187 pt).
    private let heroSpace: CGFloat = 143

    var body: some View {
        let devices = store.devices(in: room)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                // Shown here rather than with navigationSubtitle: a subtitle collapses
                // the large title of a pushed view on iOS 26.
                Text(subtitle(devices))
                    .font(.roundedSubheadline)
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .padding(.top, -6)
                    .frame(height: heroSpace - Theme.sectionSpacing, alignment: .top)
                metrics(devices)
                ForEach(store.maintenance(in: room).filter { !done.contains($0.id) }) { item in
                    MaintenanceCard(item: item) { done.insert(item.id) }
                }
                RoomHousekeepingSection(room: room) { choreDone = $0 }
                ForEach(RoomCategory.allCases, id: \.self) { category in
                    let members = devices.filter { category.contains($0) }
                    if !members.isEmpty {
                        Text(category.title)
                            .font(.roundedTitle3)
                            .padding(.leading, 4)
                            .padding(.top, 10)
                        VStack(spacing: 8) {
                            ForEach(members) { entity in
                                DeviceRow(entity: entity) { opened = OpenedDevice(id: entity.entityID) }
                            }
                        }
                    }
                }
                RoomItemsSection(room: room)
                    .padding(.top, 10)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
            .background(alignment: .top) {
                // Same crop as the mock-up: the painting is zoomed ~1.5× and its ceiling cut off.
                Color.clear
                    .frame(height: heroHeight)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { proxy in
                            Image("IllustrationRoom")
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width * 1.515, height: heroHeight * 1.316)
                                .offset(x: -proxy.size.width * 0.182, y: -heroHeight * 0.29)
                        }
                    }
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                            .frame(height: 80)
                    }
                    .padding(.horizontal, -Theme.screenPadding)
                    .offset(y: -topInset)
                    .accessibilityHidden(true)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentInsets.top }) { _, inset in
            topInset = inset
        }
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 220 }) { _, isPast in
            isPastHero = isPast
        }
        .scrollEdgeEffectHidden(!isPastHero, for: .top)
        .background(Theme.background)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle(room.name)
        .defaultScrollAnchor(.top)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .sheet(item: $opened) { DeviceSheet(entityID: $0.id) }
        .overlay(alignment: .bottom) {
            if let choreDone {
                ChoreDoneBanner(done: choreDone) { withAnimation(.smooth) { self.choreDone = nil } }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: choreDone?.id)
        .trackScreen(.room)
    }

    private func subtitle(_ devices: [EntityState]) -> String {
        let controllable = devices.filter { $0.kind != .sensor && $0.kind != .binarySensor }
        let on = controllable.filter(\.isActive).count
        return String(localized: "\(controllable.count) devices, \(on) on")
    }

    @ViewBuilder
    private func metrics(_ devices: [EntityState]) -> some View {
        let cards = metricCards(devices)
        if !cards.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(cards.indices, id: \.self) { cards[$0] }
            }
        }
    }

    private func metricCards(_ devices: [EntityState]) -> [RingMetricCard] {
        var cards: [RingMetricCard] = []
        let lights = devices.filter { $0.kind == .light }
        if !lights.isEmpty {
            let on = lights.filter { $0.state == "on" }.count
            cards.append(RingMetricCard(
                title: "Lights", value: "\(on)", unit: "/ \(lights.count)",
                caption: on == 0 ? String(localized: "All off") : String(localized: "\(on) lit"),
                symbol: "lightbulb.fill", color: .yellow, progress: Double(on) / Double(lights.count)
            ))
        }
        if let temperature = store.averageValue(of: "temperature", in: room)
            ?? devices.first(where: { $0.kind == .climate })?.currentTemperature {
            cards.append(RingMetricCard(
                title: "Temperature", value: temperature.formatted(.number.precision(.fractionLength(1))), unit: "°",
                caption: Self.comfort(temperature: temperature),
                symbol: "thermometer.sun.fill", color: .orange, progress: (temperature - 10) / 20
            ))
        }
        if let humidity = store.averageValue(of: "humidity", in: room) {
            cards.append(RingMetricCard(
                title: "Humidity", value: humidity.formatted(.number.precision(.fractionLength(0))), unit: "%",
                caption: Self.comfort(humidity: humidity),
                symbol: "drop.fill", color: .blue, progress: humidity / 100
            ))
        }
        if let motion = store.lastMotion(in: room) {
            let minutes = max(0, Int(Date.now.timeIntervalSince(motion) / 60))
            cards.append(RingMetricCard(
                title: "Motion", value: "\(min(minutes, 99))",
                unit: String(localized: "min"),
                caption: minutes == 0 ? String(localized: "Detected") : Phrasing.time(motion),
                symbol: "figure.walk.motion", color: .indigo, progress: max(0.05, 1 - Double(minutes) / 60)
            ))
        }
        return cards
    }

    static func comfort(temperature: Double) -> String {
        switch temperature {
        case ..<18: String(localized: "Cool")
        case ..<24: String(localized: "Comfortable")
        default: String(localized: "Warm")
        }
    }

    static func comfort(humidity: Double) -> String {
        switch humidity {
        case ..<35: String(localized: "Dry")
        case ..<60: String(localized: "Comfortable")
        default: String(localized: "Humid")
        }
    }
}

/// How devices are grouped inside a room.
enum RoomCategory: CaseIterable {
    case lights, climate, media, openings, appliances, sensors

    var title: LocalizedStringKey {
        switch self {
        case .lights: "Lights"
        case .climate: "Climate"
        case .media: "Media"
        case .openings: "Doors & Windows"
        case .appliances: "Appliances"
        case .sensors: "Sensors"
        }
    }

    func contains(_ entity: EntityState) -> Bool {
        switch self {
        case .lights: entity.kind == .light
        case .climate: [.climate, .fan, .humidifier].contains(entity.kind)
        case .media: entity.kind == .mediaPlayer
        case .openings:
            [.cover, .lock].contains(entity.kind)
                || (entity.kind == .binarySensor && ["door", "window", "garage_door", "opening"].contains(entity.deviceClass ?? ""))
        case .appliances: [.switch, .vacuum, .valve, .camera, .alarm].contains(entity.kind)
        case .sensors:
            entity.kind == .sensor
                || (entity.kind == .binarySensor && !["door", "window", "garage_door", "opening"].contains(entity.deviceClass ?? ""))
        }
    }
}

#Preview {
    NavigationStack {
        RoomView(room: Area(id: "living_room", name: "Salon"))
    }
    .environment(DemoHome.store())
    .environment(BelongingsStore.demo())
}

/// "Reported by the air conditioner: the filter needs cleaning", and "Done".
private struct MaintenanceCard: View {
    @Environment(HomeStore.self) private var store
    let item: MaintenanceItem
    let done: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.teal, in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.deviceName).font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                Text(title).font(.roundedHeadline)
                Text(detail).font(.roundedFootnote).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            Button(String(localized: "upkeep.done", defaultValue: "Done")) {
                Task {
                    await store.markDone(item)
                    withAnimation(.smooth) { done() }
                }
            }
            .font(.roundedSubheadlineEmphasized)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.teal.opacity(0.14), in: .capsule)
            .foregroundStyle(.teal)
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardStyle()
        .transition(.opacity)
    }

    private var symbol: String {
        switch item.kind {
        case .filter: "air.purifier.fill"
        case .battery: "battery.25percent"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch item.kind {
        case .filter: String(localized: "The filter needs cleaning")
        case .battery: String(localized: "The battery is running low")
        case .problem: String(localized: "It reports a problem")
        }
    }

    private var detail: String {
        switch item.kind {
        case .filter(let remaining): String(localized: "\(Int(remaining)) % of its life left")
        case .battery(let level): String(localized: "\(Int(level)) % left")
        case .problem: String(localized: "Check the device")
        }
    }
}
