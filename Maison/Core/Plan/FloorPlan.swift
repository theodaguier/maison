import CloudKit
import Foundation

/// The apartment seen from above, in metres: rooms, walls, doors, windows, furniture,
/// and where each device sits. Built from a RoomPlan scan, shared with the household through iCloud.
struct FloorPlan: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Hashable, Sendable {
        var x: Double
        var y: Double
    }

    struct Segment: Codable, Equatable, Sendable {
        var start: Point
        var end: Point
    }

    struct Room: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var name: String
        /// The Home Assistant area the room stands for, once associated.
        var areaID: String?
        var outline: [Point]

        /// Floor surface in square metres (shoelace formula).
        var surface: Double {
            guard outline.count > 2 else { return 0 }
            var sum = 0.0
            for index in outline.indices {
                let a = outline[index], b = outline[(index + 1) % outline.count]
                sum += a.x * b.y - b.x * a.y
            }
            return abs(sum) / 2
        }

        var center: Point {
            guard !outline.isEmpty else { return Point(x: 0, y: 0) }
            return Point(x: outline.map(\.x).reduce(0, +) / Double(outline.count),
                         y: outline.map(\.y).reduce(0, +) / Double(outline.count))
        }

        func contains(_ point: Point) -> Bool {
            var inside = false
            var j = outline.count - 1
            for i in outline.indices {
                let a = outline[i], b = outline[j]
                if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }

    /// A piece of furniture, as a rotated rectangle.
    struct Object: Codable, Equatable, Sendable {
        var category: String
        var center: Point
        var width: Double
        var depth: Double
        /// Radians, clockwise from the x axis.
        var angle: Double
    }

    var rooms: [Room]
    var walls: [Segment]
    var doors: [Segment]
    var windows: [Segment]
    var objects: [Object]
    /// Device positions by entity id.
    var devices: [String: Point] = [:]
    var scannedAt: Date
    var scannedBy: String?

    var surface: Double { rooms.map(\.surface).reduce(0, +) }

    /// The smallest rectangle around everything drawn.
    var bounds: (min: Point, max: Point) {
        let points = rooms.flatMap(\.outline) + walls.flatMap { [$0.start, $0.end] }
        guard let first = points.first else { return (Point(x: 0, y: 0), Point(x: 1, y: 1)) }
        return points.reduce((first, first)) { result, point in
            (Point(x: min(result.0.x, point.x), y: min(result.0.y, point.y)),
             Point(x: max(result.1.x, point.x), y: max(result.1.y, point.y)))
        }
    }

    func room(at point: Point) -> Room? {
        rooms.first { $0.contains(point) }
    }

    func room(forArea areaID: String) -> Room? {
        rooms.first { $0.areaID == areaID }
    }
}

// MARK: - iCloud

enum FloorPlanRecord {
    static let recordType = "FloorPlan"
    private static let field = "plan"

    static func recordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "floor-plan", zoneID: zoneID)
    }

    static func plan(from record: CKRecord) -> FloorPlan? {
        guard record.recordType == recordType, let data = record[field] as? Data else { return nil }
        return try? JSONDecoder().decode(FloorPlan.self, from: data)
    }

    static func record(_ plan: FloorPlan, in zoneID: CKRecordZone.ID) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(in: zoneID))
        record[field] = try JSONEncoder().encode(plan)
        return record
    }
}
