import Foundation

// Housekeeping itself is in the intelligence layer. What stays here is the iPhone's: a room's symbol,
// and where the log is kept until the add-on keeps it for the household.

extension RoomKind {
    var symbol: String {
        switch self {
        case .livingRoom: "sofa.fill"
        case .kitchen: "fork.knife"
        case .bedroom: "bed.double.fill"
        case .bathroom: "shower.fill"
        case .entrance: "door.left.hand.closed"
        case .office: "desktopcomputer"
        case .laundry: "washer.fill"
        case .outdoor: "leaf.fill"
        case .garage: "car.fill"
        case .other: "square.split.bottomrightquarter.fill"
        }
    }
}

extension HousekeepingLog {
    static let key = "housekeepingLog"

    static func load(from defaults: UserDefaults) -> HousekeepingLog {
        guard let data = defaults.data(forKey: key), let log = try? JSONDecoder().decode(HousekeepingLog.self, from: data) else {
            return HousekeepingLog()
        }
        return log
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
