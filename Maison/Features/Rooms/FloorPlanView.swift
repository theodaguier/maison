import SwiftUI

/// Draws the plan from above: rooms (lit ones in yellow), furniture, walls, doors, windows, room names,
/// and a marker per placed device.
struct FloorPlanView: View {
    @Environment(HomeStore.self) private var store
    let plan: FloorPlan
    /// Hides device markers (plan review after a scan).
    var showsDevices = true
    /// The device being placed: its marker follows taps and drags.
    var placing: String?
    var placingPosition: FloorPlan.Point?
    var onPlace: ((FloorPlan.Point) -> Void)?
    var onOpenDevice: ((String) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let frame = PlanFrame(plan: plan, size: proxy.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(in: &context, frame: frame) }
                ForEach(plan.rooms) { room in
                    roomLabel(room)
                        .position(frame.point(room.center))
                }
                if showsDevices {
                    ForEach(placedDevices(frame: frame), id: \.id) { device in
                        DeviceMarker(entity: device.entity, isPlacing: device.id == placing)
                            .position(device.position)
                            .onTapGesture { onOpenDevice?(device.id) }
                    }
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard placing != nil else { return }
                        onPlace?(frame.planPoint(value.location))
                    },
                including: placing == nil ? .subviews : .all
            )
        }
        .aspectRatio(PlanFrame.aspect(of: plan), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floor plan")
    }

    private struct PlacedDevice {
        let id: String
        let entity: EntityState
        let position: CGPoint
    }

    private func placedDevices(frame: PlanFrame) -> [PlacedDevice] {
        var positions = plan.devices
        if let placing, let placingPosition { positions[placing] = placingPosition }
        return positions.compactMap { id, point in
            store.states[id].map { PlacedDevice(id: id, entity: $0, position: frame.point(point)) }
        }
        .sorted { $0.id < $1.id }
    }

    private func roomLabel(_ room: FloorPlan.Room) -> some View {
        let area = room.areaID.flatMap { id in store.layout.areas.first { $0.id == id } }
        let temperature = area.flatMap { store.averageValue(of: "temperature", in: $0) }
        return VStack(spacing: 0) {
            Text(room.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            if let temperature {
                Text(EntityState.degrees(temperature))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if !showsDevices {
                Text("\(room.surface.formatted(.number.precision(.fractionLength(1)))) m²")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .allowsHitTesting(false)
    }

    private func isLit(_ room: FloorPlan.Room) -> Bool {
        guard showsDevices, let areaID = room.areaID, let area = store.layout.areas.first(where: { $0.id == areaID }) else { return false }
        return store.devices(in: area).contains { $0.kind == .light && $0.isActive }
    }

    private func draw(in context: inout GraphicsContext, frame: PlanFrame) {
        for room in plan.rooms where room.outline.count > 2 {
            var path = Path()
            path.addLines(room.outline.map(frame.point))
            path.closeSubpath()
            context.fill(path, with: .color(isLit(room) ? Color(red: 1, green: 0.96, blue: 0.82) : Color(.secondarySystemBackground)))
        }
        for object in plan.objects {
            let size = CGSize(width: object.width * frame.scale, height: object.depth * frame.scale)
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            var copy = context
            let center = frame.point(object.center)
            copy.translateBy(x: center.x, y: center.y)
            copy.rotate(by: .radians(object.angle))
            copy.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Color(.systemGray5)))
        }
        for wall in plan.walls {
            context.stroke(line(wall, frame), with: .color(.primary), style: StrokeStyle(lineWidth: 4, lineCap: .square))
        }
        for door in plan.doors {
            context.stroke(line(door, frame), with: .color(Color(.systemBackground)), style: StrokeStyle(lineWidth: 6))
            // The leaf, swung open a quarter turn.
            let start = frame.point(door.start), end = frame.point(door.end)
            let radius = hypot(end.x - start.x, end.y - start.y)
            let angle = atan2(end.y - start.y, end.x - start.x)
            var arc = Path()
            arc.addArc(center: start, radius: radius, startAngle: .radians(angle), endAngle: .radians(angle + .pi / 2), clockwise: false)
            context.stroke(arc, with: .color(Color(.systemGray3)), lineWidth: 1)
        }
        for window in plan.windows {
            context.stroke(line(window, frame), with: .color(Color(.systemBackground)), style: StrokeStyle(lineWidth: 4))
            context.stroke(line(window, frame), with: .color(Color.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 2))
        }
    }

    private func line(_ segment: FloorPlan.Segment, _ frame: PlanFrame) -> Path {
        var path = Path()
        path.move(to: frame.point(segment.start))
        path.addLine(to: frame.point(segment.end))
        return path
    }
}

/// Maps metres on the plan to points on screen, keeping proportions.
struct PlanFrame {
    let origin: FloorPlan.Point
    let scale: Double
    let inset: Double = 8

    init(plan: FloorPlan, size: CGSize) {
        let bounds = plan.bounds
        let width = max(bounds.max.x - bounds.min.x, 0.1), height = max(bounds.max.y - bounds.min.y, 0.1)
        origin = bounds.min
        scale = min((size.width - 16) / width, (size.height - 16) / height)
    }

    static func aspect(of plan: FloorPlan) -> CGFloat {
        let bounds = plan.bounds
        return max(bounds.max.x - bounds.min.x, 0.1) / max(bounds.max.y - bounds.min.y, 0.1)
    }

    func point(_ point: FloorPlan.Point) -> CGPoint {
        CGPoint(x: inset + (point.x - origin.x) * scale, y: inset + (point.y - origin.y) * scale)
    }

    func planPoint(_ point: CGPoint) -> FloorPlan.Point {
        FloorPlan.Point(x: (point.x - inset) / scale + origin.x, y: (point.y - inset) / scale + origin.y)
    }
}

private struct DeviceMarker: View {
    let entity: EntityState
    var isPlacing = false

    var body: some View {
        let isOn = entity.isActive && entity.kind != .sensor
        Image(systemName: entity.symbolName)
            .font(.system(size: isPlacing ? 15 : 11, weight: .semibold))
            .foregroundStyle(isOn || isPlacing ? Color.white : Color.secondary)
            .frame(width: isPlacing ? 38 : 24, height: isPlacing ? 38 : 24)
            .background(isPlacing ? Color.blue : isOn ? entity.accent : Color(.systemBackground), in: .circle)
            .overlay { Circle().strokeBorder(isOn || isPlacing ? Color.white : Theme.cardBorder, lineWidth: 1.5) }
            .overlay {
                if isPlacing {
                    Circle().stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 56, height: 56)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .accessibilityLabel(entity.name)
    }
}
