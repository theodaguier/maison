import Foundation

/// One notable thing about the day, computed from the server's history.
/// The day summary is written from these: the language model rewords them, it never adds a number.
struct DayFact: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case temperature
        case climate(heating: Bool)
        case lock(locked: Bool)
        case energy
        case automations
    }

    let kind: Kind
    let title: String
    var detail: String = ""

    var id: String { title }

    /// The fact as one line of the model's prompt.
    var promptLine: String { detail.isEmpty ? "- \(title)" : "- \(title) (\(detail))" }
}

extension HomeStore {
    /// What stood out today, in the order the summary sheet lists it.
    func dayFacts(now: Date = .now) async -> [DayFact] {
        let calendar = Calendar.current
        let today = DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        var facts: [DayFact] = []
        if let peak = await temperaturePeak(today: today) { facts.append(peak) }
        facts += await climateRuns(today: today, now: now)
        facts += await lockEvents(today: today)
        if let energy = await energyUse() { facts.append(energy) }
        facts += await automationsRun(today: today)
        return facts
    }

    /// The warmest hour of the day across indoor sensors, compared with yesterday's warmest.
    private func temperaturePeak(today: DateInterval) async -> DayFact? {
        let yesterdayStart = today.start.addingTimeInterval(-86_400)
        var peak: (sensor: EntityState, value: Double, hour: Date)?
        var yesterdayPeak: Double?
        for sensor in indoorTemperatureSensors {
            for point in await statistics(of: sensor.entityID, since: yesterdayStart, period: "hour") {
                guard let value = point.max ?? point.mean else { continue }
                if point.start < today.start {
                    yesterdayPeak = max(yesterdayPeak ?? value, value)
                } else if value > (peak?.value ?? -.infinity) {
                    peak = (sensor, value, point.start)
                }
            }
        }
        guard let peak else { return nil }

        let degrees = EntityState.degrees(peak.value)
        let title = if let room = area(of: peak.sensor)?.name {
            String(localized: "Peak of \(degrees) \(Phrasing.location(room))")
        } else {
            String(localized: "Peak of \(degrees)")
        }
        var detail = String(localized: "Around \(Phrasing.hour(peak.hour))")
        if let yesterdayPeak {
            let change = peak.value - yesterdayPeak
            let difference = abs(change).formatted(.number.precision(.fractionLength(1)))
            if abs(change) < 0.3 {
                detail += " · " + String(localized: "as warm as yesterday")
            } else if change > 0 {
                detail += " · " + String(localized: "\(difference)° warmer than yesterday")
            } else {
                detail += " · " + String(localized: "\(difference)° cooler than yesterday")
            }
        }
        return DayFact(kind: .temperature, title: title, detail: detail)
    }

    /// How long each heater or air conditioner ran today, when it ran at all.
    private func climateRuns(today: DateInterval, now: Date) async -> [DayFact] {
        var facts: [DayFact] = []
        for climate in devices.filter({ $0.kind == .climate }) {
            let changes = await changes(of: climate.entityID, since: today.start)
            let usage = DayUsage(changes: changes, day: today, now: now) { !["off", "unavailable", "unknown"].contains($0) }
            guard usage.total >= 5 * 60 else { continue }
            let duration = Duration.seconds(usage.total).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            var details: [String] = []
            if let room = area(of: climate)?.name { details.append(room) }
            if let target = climate.targetTemperature {
                details.append(String(localized: "set to \(EntityState.degrees(target))"))
            }
            facts.append(DayFact(
                kind: .climate(heating: changes.contains { $0.state == "heat" }),
                title: String(localized: "\(Phrasing.subject(climate.name)) ran for \(duration)"),
                detail: details.joined(separator: " · ")
            ))
        }
        return facts
    }

    /// The last time each lock was locked or unlocked today, and by whom.
    private func lockEvents(today: DateInterval) async -> [DayFact] {
        var facts: [DayFact] = []
        for lock in devices.filter({ $0.kind == .lock }) {
            let entries = await logbook(of: lock.entityID, since: today.start)
            guard let last = entries.last(where: { $0.date >= today.start && ["locked", "unlocked"].contains($0.state ?? "") }) else { continue }
            let isLocked = last.state == "locked"
            let state = Phrasing.agree(isLocked ? String(localized: "Locked") : String(localized: "Unlocked"), with: lock.name)
            let detail = if let automation = last.automationName {
                String(localized: "By “\(automation)”")
            } else if let person = last.userID.flatMap(personName(userID:)) {
                String(localized: "By \(person)")
            } else {
                ""
            }
            facts.append(DayFact(
                kind: .lock(locked: isLocked),
                title: String(localized: "\(Phrasing.subject(lock.name)) \(state.lowercased()) at \(Phrasing.time(last.date))"),
                detail: detail
            ))
        }
        return facts
    }

    /// Today's energy use, compared with the same time yesterday.
    private func energyUse() async -> DayFact? {
        guard let energy = energyToday, let value = energy.numericState else { return nil }
        let amount = value.formatted(.number.precision(.fractionLength(0...1)))
        let title = String(localized: "\(amount) \(energy.unit ?? "kWh") used")
        guard let change = await changeSinceYesterday(of: energy), value - change > 0 else {
            return DayFact(kind: .energy, title: title)
        }
        let percent = Int((abs(change) / (value - change) * 100).rounded())
        let detail = switch percent {
        case 0: String(localized: "Same as yesterday at this time")
        case _ where change < 0: String(localized: "\(percent)% less than yesterday at this time")
        default: String(localized: "\(percent)% more than yesterday at this time")
        }
        return DayFact(kind: .energy, title: title, detail: detail)
    }

    /// The automations that ran today, busiest first, each with how many times it ran.
    private func automationsRun(today: DateInterval) async -> [DayFact] {
        let runs = await automationRuns().filter { $0.didRun && today.contains($0.start) }
        var counts: [(name: String, runs: Int)] = []
        for id in runs.sorted(by: { $0.start < $1.start }).map(\.automationID) {
            let name = automations.first { $0.attributes["id"]?.stringValue == id }?.name ?? id
            if let index = counts.firstIndex(where: { $0.name == name }) {
                counts[index].runs += 1
            } else {
                counts.append((name, 1))
            }
        }
        // One line per rule: "4 automation runs" reads as four automations to the model.
        return counts.sorted { $0.runs > $1.runs }.prefix(3).map {
            DayFact(kind: .automations, title: String(localized: "“\($0.name)” ran \($0.runs) times"))
        }
    }
}
