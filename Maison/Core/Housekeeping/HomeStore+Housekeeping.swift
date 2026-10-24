import Foundation

extension HomeStore {
    /// What the room's devices hint at, for a room its icon and name don't name.
    func roomHints(in area: Area) -> Set<RoomHint> {
        var hints: Set<RoomHint> = []
        for entity in devices(in: area) {
            if entity.kind == .lock { hints.insert(.lock) }
            if entity.kind == .mediaPlayer, entity.deviceClass == "tv" { hints.insert(.television) }
        }
        return hints
    }

    func roomKindGuess(_ area: Area) -> RoomKindGuess {
        RoomKind.recognize(name: area.name, icon: area.icon, hints: roomHints(in: area))
    }

    /// The type the person chose or confirmed, otherwise Maison's guess.
    func roomKind(_ area: Area) -> RoomKind {
        housekeepingLog.kinds[area.id] ?? roomKindGuess(area).kind
    }

    /// The one room Maison asks about: no type chosen, and nothing sure in its icon or name.
    var roomToConfirm: (area: Area, guess: RoomKindGuess)? {
        for area in layout.areas where housekeepingLog.kinds[area.id] == nil {
            let guess = roomKindGuess(area)
            if !guess.isSure { return (area, guess) }
        }
        return nil
    }

    func roomSignals(in area: Area) -> RoomSignals {
        RoomSignals(humidity: averageValue(of: "humidity", in: area), particles: averageValue(of: "pm25", in: area))
    }

    /// The room's chores, soonest first.
    func chores(in area: Area, now: Date = .now) -> [ChoreStatus] {
        housekeepingLog.statuses(roomID: area.id, kind: roomKind(area), signals: roomSignals(in: area), now: now)
    }

    /// Every room's chores, soonest first.
    func allChores(now: Date = .now) -> [ChoreStatus] {
        layout.areas.flatMap { chores(in: $0, now: now) }.sorted { $0.due < $1.due }
    }

    /// The robot vacuum, if the home has one: Maison starts it.
    var robotVacuum: EntityState? {
        states.values.filter { $0.kind == .vacuum }.min { $0.entityID < $1.entityID }
    }

    func startRobot() async {
        guard let robot = robotVacuum else { return }
        await call("vacuum", "start", on: robot)
    }
}
