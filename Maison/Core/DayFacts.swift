import Foundation

extension HomeStore {
    /// What stood out today, in the order the summary sheet lists it.
    func dayFacts(now: Date = .now) async -> [DayFact] {
        let today = DateInterval(start: Calendar.current.startOfDay(for: now), duration: 86_400)
        return await DayFacts.compute(dayInputs(today: today, now: now), day: today, now: now)
    }

    /// The history the day's facts are computed from.
    func dayInputs(today: DateInterval, now: Date) async -> DayInputs {
        var inputs = DayInputs()
        let yesterdayStart = today.start.addingTimeInterval(-86_400)
        for sensor in indoorTemperatureSensors {
            inputs.thermometers.append(.init(
                entityID: sensor.entityID,
                room: area(of: sensor)?.name,
                points: await statistics(of: sensor.entityID, since: yesterdayStart, period: "hour")
            ))
        }
        for climate in devices.filter({ $0.kind == .climate }) {
            inputs.climates.append(.init(
                entityID: climate.entityID,
                name: climate.name,
                room: area(of: climate)?.name,
                target: climate.targetTemperature,
                changes: await changes(of: climate.entityID, since: today.start)
            ))
        }
        for lock in devices.filter({ $0.kind == .lock }) {
            inputs.locks.append(.init(
                entityID: lock.entityID,
                name: lock.name,
                entries: await logbook(of: lock.entityID, since: today.start)
            ))
        }
        inputs.energy = await energyScore(now: now, weekAgo: now.addingTimeInterval(-8 * 86_400))
        inputs.automationRuns = await automationRuns()
        for automation in automations {
            if let id = automation.attributes["id"]?.stringValue { inputs.automationNames[id] = automation.name }
        }
        for person in states.values where person.domain == "person" {
            if let userID = person.attributes["user_id"]?.stringValue { inputs.people[userID] = person.name }
        }
        return inputs
    }
}
