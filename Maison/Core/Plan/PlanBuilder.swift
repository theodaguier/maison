import Foundation
import RoomPlan
import simd

/// Turns a RoomPlan scan into a flat plan seen from above (x to the right, y away from the starting point).
enum PlanBuilder {
    static func plan(from structure: CapturedStructure, areas: [Area], keeping old: FloorPlan?, scannedBy: String?) -> FloorPlan {
        var usedAreas = Set<String>()
        let rooms = structure.rooms.enumerated().map { index, room -> FloorPlan.Room in
            let outline = outline(of: room)
            let label = room.sections.first?.label ?? structure.sections.first { section in
                FloorPlan.Room(id: UUID(), name: "", outline: outline).contains(point(section.center))
            }?.label
            let name = label.flatMap(roomName) ?? String(localized: "Room \(index + 1)")
            // A room already named like an area is associated straight away.
            let area = areas.first { !usedAreas.contains($0.id) && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            if let area { usedAreas.insert(area.id) }
            return FloorPlan.Room(id: room.identifier, name: area?.name ?? name, areaID: area?.id, outline: outline)
        }
        var plan = FloorPlan(
            rooms: rooms,
            walls: structure.walls.map(segment),
            doors: (structure.doors + structure.openings).map(segment),
            windows: structure.windows.map(segment),
            objects: structure.objects.map(object),
            scannedAt: .now,
            scannedBy: scannedBy
        )
        // Devices placed on a previous plan stay where they were if they still fall inside it.
        if let old {
            plan.devices = old.devices.filter { plan.room(at: $0.value) != nil }
        }
        return plan
    }

    static func roomName(_ label: CapturedRoom.Section.Label) -> String? {
        switch label {
        case .livingRoom: String(localized: "Living Room")
        case .bedroom: String(localized: "Bedroom")
        case .bathroom: String(localized: "Bathroom")
        case .kitchen: String(localized: "Kitchen")
        case .diningRoom: String(localized: "Dining Room")
        default: nil
        }
    }

    // MARK: Geometry

    private static func point(_ vector: simd_float3) -> FloorPlan.Point {
        FloorPlan.Point(x: Double(vector.x), y: Double(vector.z))
    }

    private static func segment(_ surface: CapturedRoom.Surface) -> FloorPlan.Segment {
        let center = surface.transform.columns.3
        let direction = simd_normalize(simd_float2(surface.transform.columns.0.x, surface.transform.columns.0.z))
        let half = direction * surface.dimensions.x / 2
        return FloorPlan.Segment(
            start: FloorPlan.Point(x: Double(center.x - half.x), y: Double(center.z - half.y)),
            end: FloorPlan.Point(x: Double(center.x + half.x), y: Double(center.z + half.y))
        )
    }

    private static func object(_ object: CapturedRoom.Object) -> FloorPlan.Object {
        let center = object.transform.columns.3
        let axis = object.transform.columns.0
        return FloorPlan.Object(
            category: String(describing: object.category),
            center: FloorPlan.Point(x: Double(center.x), y: Double(center.z)),
            width: Double(object.dimensions.x),
            depth: Double(object.dimensions.z),
            angle: Double(atan2(axis.z, axis.x))
        )
    }

    /// The floor's corners when RoomPlan measured them, otherwise the box around the room's walls.
    private static func outline(of room: CapturedRoom) -> [FloorPlan.Point] {
        if let floor = room.floors.first, floor.polygonCorners.count > 2 {
            return floor.polygonCorners.map { corner in
                let world = floor.transform * simd_float4(corner.x, corner.y, corner.z, 1)
                return FloorPlan.Point(x: Double(world.x), y: Double(world.z))
            }
        }
        let ends = room.walls.flatMap { wall -> [FloorPlan.Point] in
            let segment = segment(wall)
            return [segment.start, segment.end]
        }
        guard let minX = ends.map(\.x).min(), let maxX = ends.map(\.x).max(),
              let minY = ends.map(\.y).min(), let maxY = ends.map(\.y).max() else { return [] }
        return [.init(x: minX, y: minY), .init(x: maxX, y: minY), .init(x: maxX, y: maxY), .init(x: minX, y: maxY)]
    }
}
