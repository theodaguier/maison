import Foundation

/// What a room is for. It gives the room its housekeeping: which chores, and how often.
enum RoomKind: String, CaseIterable, Codable, Sendable {
    case livingRoom, kitchen, bedroom, bathroom, entrance, office, laundry, outdoor, garage, other

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

    /// The room's chores and their usual rhythm, in days. Always the room's, never an object's:
    /// an oven or a mattress waits with the inventory.
    var chores: [(chore: Chore, days: Int)] {
        switch self {
        case .livingRoom: [(.vacuum, 7), (.dust, 14)]
        case .kitchen: [(.worktop, 1), (.floors, 7)]
        case .bedroom: [(.sheets, 7), (.vacuum, 7)]
        case .bathroom: [(.sink, 7), (.shower, 7), (.toilet, 7), (.towels, 7)]
        case .entrance: [(.floors, 7), (.doormat, 30)]
        case .office: [(.desk, 14), (.vacuum, 7)]
        case .laundry: [(.floors, 30)]
        case .outdoor: [(.terrace, 30)]
        case .garage: [(.floors, 90)]
        case .other: [(.vacuum, 14), (.dust, 14)]
        }
    }

    /// From the room's icon and name in the source, then from its devices.
    /// The icon and the name are sure enough; devices alone are only a guess, which Maison asks about.
    static func recognize(name: String, icon: String?, hints: Set<RoomHint> = []) -> RoomKindGuess {
        if let icon, let kind = kind(icon: icon) { return RoomKindGuess(kind: kind, basis: .icon) }
        if let kind = kind(name: name) { return RoomKindGuess(kind: kind, basis: .name) }
        if hints.contains(.lock) { return RoomKindGuess(kind: .entrance, basis: .devices) }
        if hints.contains(.television) { return RoomKindGuess(kind: .livingRoom, basis: .devices) }
        return RoomKindGuess(kind: .other, basis: .nothing)
    }

    private static let iconPrefixes: [(RoomKind, [String])] = [
        (.bathroom, ["shower", "bathtub", "toilet", "paper-roll"]),
        (.laundry, ["washing-machine", "tumble-dryer", "hanger", "iron"]),
        (.livingRoom, ["sofa", "television", "fireplace"]),
        (.kitchen, ["stove", "fridge", "chef-hat", "silverware", "pot", "countertop", "microwave"]),
        (.bedroom, ["bed", "bunk-bed"]),
        (.entrance, ["door", "coat-rack", "shoe"]),
        (.office, ["desk", "laptop", "monitor", "briefcase", "chair-rolling"]),
        (.outdoor, ["flower", "tree", "grass", "pine-tree", "pool", "balcony", "sprout", "nature"]),
        (.garage, ["garage", "car"]),
    ]

    /// Several languages, without accents: Home Assistant names rooms in the household's own words.
    private static let nameWords: [(RoomKind, [String])] = [
        (.bathroom, ["salle de bain", "salle d'eau", "bain", "douche", "bath", "shower", "wc", "toilet", "badezimmer", "bano"]),
        (.laundry, ["buanderie", "cellier", "laundry", "utility", "waschkuche", "lavanderia"]),
        (.livingRoom, ["salon", "sejour", "salle a manger", "living", "lounge", "dining", "wohnzimmer", "soggiorno", "salotto"]),
        (.kitchen, ["cuisine", "kitchen", "kuche", "cocina", "cucina"]),
        (.bedroom, ["chambre", "bedroom", "suite parentale", "nursery", "schlafzimmer", "dormitorio", "camera da letto"]),
        (.entrance, ["entree", "entrance", "couloir", "hall", "corridor", "vestibule", "flur"]),
        (.office, ["bureau", "office", "study", "arbeitszimmer", "despacho"]),
        (.outdoor, ["jardin", "terrasse", "balcon", "garden", "terrace", "balcony", "patio", "garten"]),
        (.garage, ["garage"]),
    ]

    /// The words of `name` that name a kind of room, as written there ("Lampe Cuisine" gives "Cuisine"),
    /// to suggest a room for a device that is in none. Whole words only.
    static func roomWord(in name: String) -> String? {
        let characters = Array(name)
        // Folded one character at a time, so that a match in the folded name maps back onto the name.
        let foldedCharacters = characters.map { DeviceNaming.fold(String($0)) }
        guard foldedCharacters.allSatisfy({ $0.count == 1 }) else { return nil }
        let folded = foldedCharacters.joined()
        for (_, words) in nameWords {
            for word in words.sorted(by: { $0.count > $1.count }) {
                guard let range = DeviceNaming.wholeWordRange(of: word, in: folded) else { continue }
                let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
                let length = folded.distance(from: range.lowerBound, to: range.upperBound)
                let found = String(characters[start..<(start + length)])
                return found.prefix(1).uppercased() + found.dropFirst()
            }
        }
        return nil
    }

    private static func kind(icon: String) -> RoomKind? {
        let name = icon.hasPrefix("mdi:") ? String(icon.dropFirst(4)) : icon
        return iconPrefixes.first { $0.1.contains(where: name.hasPrefix) }?.0
    }

    private static func kind(name: String) -> RoomKind? {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
        return nameWords.first { $0.1.contains(where: folded.contains) }?.0
    }
}

/// Something a room's devices say about what it is for.
enum RoomHint: Hashable, Sendable {
    case lock
    case television
}

struct RoomKindGuess: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        case icon, name, devices, nothing
    }

    let kind: RoomKind
    let basis: Basis

    /// Used without asking. Otherwise Maison asks once, in Rooms.
    var isSure: Bool { basis == .icon || basis == .name }
}

/// A room's chore. Always the room's, never an object's.
enum Chore: String, CaseIterable, Codable, Sendable {
    case vacuum, dust, worktop, floors, sheets, sink, shower, toilet, towels, doormat, desk, terrace
}

/// What the room's own sensors measure, which brings a chore forward.
struct RoomSignals: Equatable, Sendable {
    /// Average relative humidity, in percent.
    var humidity: Double?
    /// Fine particles (PM2.5), in µg/m³.
    var particles: Double?

    /// A bathroom that stays this humid is cleaned twice as often.
    static let humidityLimit = 70.0
    /// Dust settles faster above this.
    static let particlesLimit = 25.0
}

/// Why a chore comes sooner than its room's rhythm: a measured value.
enum RhythmReason: Equatable, Sendable {
    case humidity(Double)
    case particles(Double)
}

extension Chore {
    /// The chore's rhythm in this room, brought forward by what the room measures.
    func rhythm(usual days: Int, signals: RoomSignals) -> (days: Int, reason: RhythmReason?) {
        if [.shower, .sink].contains(self), let humidity = signals.humidity, humidity >= RoomSignals.humidityLimit {
            return (max(1, days / 2), .humidity(humidity))
        }
        if [.vacuum, .dust, .floors].contains(self), let particles = signals.particles, particles >= RoomSignals.particlesLimit {
            return (max(1, days / 2), .particles(particles))
        }
        return (days, nil)
    }
}

/// One chore in one room: when it was last done, and when it comes back.
struct ChoreStatus: Identifiable, Equatable, Sendable {
    let roomID: String
    let chore: Chore
    let days: Int
    let reason: RhythmReason?
    let lastDone: Date
    /// Entered when someone marked it done; estimated while Maison only knows when it first saw the room.
    let origin: ValueOrigin
    let due: Date

    var id: String { "\(roomID)/\(chore.rawValue)" }

    /// Whole days until it is due: negative once late, 0 on the day.
    func daysLeft(now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
    }

    func isLate(now: Date = .now, calendar: Calendar = .current) -> Bool { daysLeft(now: now, calendar: calendar) < 0 }

    /// What is left of the interval, from 1 (just done) to 0 (due or late).
    func remaining(now: Date = .now) -> Double {
        let interval = due.timeIntervalSince(lastDone)
        guard interval > 0 else { return 0 }
        return min(1, max(0, due.timeIntervalSince(now) / interval))
    }
}

/// What was done, and the type chosen for each room, kept on the iPhone until the add-on keeps it for the household.
struct HousekeepingLog: Codable, Equatable, Sendable {
    /// Last time each chore was done, keyed "room/chore".
    var done: [String: Date] = [:]
    /// When Maison first saw each room.
    var firstSeen: [String: Date] = [:]
    /// The type the person chose or confirmed for a room, which wins over any guess.
    var kinds: [String: RoomKind] = [:]

    init(done: [String: Date] = [:], firstSeen: [String: Date] = [:], kinds: [String: RoomKind] = [:]) {
        self.done = done
        self.firstSeen = firstSeen
        self.kinds = kinds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = try container.decodeIfPresent([String: Date].self, forKey: .done) ?? [:]
        firstSeen = try container.decodeIfPresent([String: Date].self, forKey: .firstSeen) ?? [:]
        kinds = try container.decodeIfPresent([String: RoomKind].self, forKey: .kinds) ?? [:]
    }

    /// Notes the chore done and returns when it was done before, to undo it.
    @discardableResult
    mutating func markDone(_ chore: Chore, in roomID: String, at date: Date = .now) -> Date? {
        done.updateValue(date, forKey: "\(roomID)/\(chore.rawValue)")
    }

    /// Puts back what was there before "Done".
    mutating func restore(_ chore: Chore, in roomID: String, to previous: Date?) {
        done["\(roomID)/\(chore.rawValue)"] = previous
    }

    mutating func noteSeen(_ roomIDs: [String], at date: Date = .now) {
        for id in roomIDs where firstSeen[id] == nil {
            firstSeen[id] = date
        }
    }

    /// The room's chores, soonest first. A chore never marked is assumed half-way through its rhythm
    /// on the day Maison first saw the room, so a new home doesn't open with everything late.
    func statuses(roomID: String, kind: RoomKind, signals: RoomSignals, now: Date = .now) -> [ChoreStatus] {
        kind.chores.map { chore, usual in
            let rhythm = chore.rhythm(usual: usual, signals: signals)
            let interval = TimeInterval(rhythm.days) * 86_400
            let marked = done["\(roomID)/\(chore.rawValue)"]
            let last = marked ?? (firstSeen[roomID] ?? now).addingTimeInterval(-interval / 2)
            return ChoreStatus(
                roomID: roomID, chore: chore, days: rhythm.days, reason: rhythm.reason,
                lastDone: last, origin: marked == nil ? .estimated : .entered, due: last.addingTimeInterval(interval)
            )
        }
        .sorted { $0.due < $1.due }
    }

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
