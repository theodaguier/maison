import SwiftUI

// What a step of a rule can be, grouped as people think of it: what Maison knows, a moment, the people,
// the home. An entry only appears when the home can do it: no calendar, no calendar event.

struct CatalogEntry<Step>: Identifiable {
    let id: String
    let symbol: String
    let color: Color
    let title: String
    let example: String
    let make: () -> Step
}

struct CatalogSection<Step>: Identifiable {
    let title: String
    let entries: [CatalogEntry<Step>]
    var id: String { title }
}

extension HomeStore {
    /// The tariff entered in Maison, or the sample one in the demo.
    var energyTariff: EnergyTariff? { isDemoHome ? DemoHome.tariff : EnergyTariff.load() }

    // MARK: Triggers

    func triggerCatalog() -> [CatalogSection<AutomationRule.Trigger>] {
        typealias Entry = CatalogEntry<AutomationRule.Trigger>
        var known: [Entry] = []
        if let offPeak = energyTariff?.offPeak {
            known.append(Entry(id: "offPeak", symbol: "clock.fill", color: .indigo, title: String(localized: "Off-peak hours start"),
                               example: String(localized: "from your tariff")) { .time(at: RuleTime.hour(offPeak.startHour)) })
        }
        if let internet = internetSources?.connectivity {
            known.append(Entry(id: "internet", symbol: "wifi.exclamationmark", color: .indigo, title: String(localized: "Internet is down"),
                               example: String(localized: "for more than 2 minutes")) {
                    .state(entityID: internet.entityID, to: "off", forMinutes: 2)
                })
        }
        var moment: [Entry] = [
            Entry(id: "time", symbol: "clock.fill", color: .blue, title: String(localized: "At a time"),
                  example: String(localized: "Every day at \(RuleTime.display("07:30:00"))")) { .time(at: "19:00:00") },
            Entry(id: "sun", symbol: "sunset.fill", color: .orange, title: String(localized: "Sunrise or sunset"),
                  example: RuleTime.sunText(.sunset, offset: -30)) { .sun(.sunset, offset: 0) },
            Entry(id: "interval", symbol: "arrow.triangle.2.circlepath", color: .blue, title: String(localized: "At a regular interval"),
                  example: RuleTime.intervalText(15)) { .interval(minutes: 15) },
        ]
        if let calendar = states.values.filter({ $0.domain == "calendar" }).sortedByName().first {
            moment.append(Entry(id: "calendar", symbol: "calendar", color: .red, title: String(localized: "A calendar event"),
                                example: String(localized: "When an event of “\(calendar.name)” starts")) {
                    .calendar(entityID: calendar.entityID, atStart: true)
                })
        }
        let home: [Entry] = [
            Entry(id: "device", symbol: "switch.2", color: .teal, title: String(localized: "A device changes"),
                  example: String(localized: "The front door opens")) { .state(entityID: "", to: nil, forMinutes: nil) },
            Entry(id: "threshold", symbol: "thermometer.medium", color: .orange, title: String(localized: "A measurement crosses a value"),
                  example: String(localized: "Living room above 25°")) { .threshold(entityID: "", above: 25, below: nil) },
            Entry(id: "presence", symbol: "figure.walk.departure", color: .indigo, title: String(localized: "Arrivals and departures"),
                  example: String(localized: "When everyone leaves")) { .everyoneLeaves },
        ]
        return [
            CatalogSection(title: String(localized: "What Maison knows"), entries: known),
            CatalogSection(title: String(localized: "Moment"), entries: moment),
            CatalogSection(title: String(localized: "Home"), entries: home),
        ].filter { !$0.entries.isEmpty }
    }

    /// The catalog entry a trigger belongs to; `nil` for one set up in Home Assistant.
    func catalogID(of trigger: AutomationRule.Trigger) -> String? {
        switch trigger {
        case .time(let at): offPeakHour(at) != nil ? "offPeak" : "time"
        case .sun: "sun"
        case .interval: "interval"
        case .calendar: "calendar"
        case .state(let id, let to, _): id == internetSources?.connectivity.entityID && to == "off" ? "internet" : "device"
        case .threshold: "threshold"
        case .everyoneLeaves, .someoneArrives: "presence"
        case .other: nil
        }
    }

    /// Whether `time` is the start or the end of the off-peak hours.
    func offPeakHour(_ time: String) -> (isStart: Bool, hour: Int)? {
        guard let offPeak = energyTariff?.offPeak else { return nil }
        if time == RuleTime.hour(offPeak.startHour) { return (true, offPeak.startHour) }
        if time == RuleTime.hour(offPeak.endHour) { return (false, offPeak.endHour) }
        return nil
    }

    // MARK: Conditions

    func conditionCatalog() -> [CatalogSection<AutomationRule.Condition>] {
        typealias Entry = CatalogEntry<AutomationRule.Condition>
        var known: [Entry] = []
        if let offPeak = energyTariff?.offPeak {
            known.append(Entry(id: "offPeak", symbol: "clock.fill", color: .indigo, title: String(localized: "During off-peak hours"),
                               example: String(localized: "from your tariff")) {
                    .between(after: RuleTime.hour(offPeak.startHour), before: RuleTime.hour(offPeak.endHour))
                })
        }
        let moment: [Entry] = [
            Entry(id: "sun", symbol: "sunset.fill", color: .orange, title: String(localized: "Day or night"),
                  example: String(localized: "Only after sunset")) { .afterSunset },
            Entry(id: "time", symbol: "clock.fill", color: .blue, title: String(localized: "Time range"),
                  example: String(localized: "Between \(RuleTime.display("23:00:00")) and \(RuleTime.display("07:00:00"))")) {
                .between(after: "23:00:00", before: "07:00:00")
            },
            Entry(id: "days", symbol: "calendar", color: .red, title: String(localized: "Days of the week"),
                  example: String(localized: "On weekdays")) { .weekdays(["mon", "tue", "wed", "thu", "fri"]) },
        ]
        var people: [Entry] = [
            Entry(id: "presence", symbol: "person.2.fill", color: .indigo, title: String(localized: "Household presence"),
                  example: String(localized: "Someone is home")) { .someoneHome },
        ]
        let persons = states.values.filter { $0.domain == "person" }.sortedByName()
        if let person = persons.first {
            people.append(Entry(id: "person", symbol: "person.crop.circle.badge.checkmark", color: .indigo, title: String(localized: "A specific person"),
                                example: String(localized: "\(person.name) is away")) { .state(entityID: person.entityID, state: "not_home") })
        }
        let home: [Entry] = [
            Entry(id: "device", symbol: "switch.2", color: .teal, title: String(localized: "A device’s state"),
                  example: String(localized: "The front door is locked")) { .state(entityID: "", state: "on") },
            Entry(id: "threshold", symbol: "gauge.with.dots.needle.33percent", color: .orange, title: String(localized: "A measurement’s value"),
                  example: String(localized: "Bathroom above 70 %")) { .threshold(entityID: "", above: 70, below: nil) },
        ]
        return [
            CatalogSection(title: String(localized: "What Maison knows"), entries: known),
            CatalogSection(title: String(localized: "Moment"), entries: moment),
            CatalogSection(title: String(localized: "People"), entries: people),
            CatalogSection(title: String(localized: "Home"), entries: home),
        ].filter { !$0.entries.isEmpty }
    }

    func catalogID(of condition: AutomationRule.Condition) -> String? {
        switch condition {
        case .between(let after, let before): isOffPeak(after: after, before: before) ? "offPeak" : "time"
        case .afterSunset, .beforeSunrise: "sun"
        case .weekdays: "days"
        case .someoneHome, .nobodyHome: "presence"
        case .state(let id, _): id.hasPrefix("person.") ? "person" : "device"
        case .threshold: "threshold"
        case .other: nil
        }
    }

    func isOffPeak(after: String, before: String) -> Bool {
        guard let offPeak = energyTariff?.offPeak else { return false }
        return after == RuleTime.hour(offPeak.startHour) && before == RuleTime.hour(offPeak.endHour)
    }

    // MARK: Actions

    func actionCatalog(notifyServices: [String]) -> [CatalogSection<AutomationRule.Action>] {
        typealias Entry = CatalogEntry<AutomationRule.Action>
        var devices: [Entry] = [
            Entry(id: "device", symbol: "switch.2", color: .orange, title: String(localized: "Control a device"),
                  example: String(localized: "Floor lamp, turn on at 60 %")) { .device(entityID: "", service: "", data: [:]) },
        ]
        let lit = rooms.filter { room in self.devices.contains { $0.kind == .light && area(of: $0)?.id == room.id } }
        if let room = lit.first {
            devices.append(Entry(id: "roomLights", symbol: "lightbulb.2.fill", color: .yellow, title: String(localized: "Lights of a room"),
                                 example: String(localized: "Turn off the lights \(Phrasing.location(room.name))")) { .roomLights(areaID: room.id, on: false) })
        }
        var run: [Entry] = []
        if let scene = states.values.filter({ $0.domain == "scene" }).sortedByName().first {
            run.append(Entry(id: "scene", symbol: "play.fill", color: .orange, title: String(localized: "A scene"), example: scene.name) {
                .scene(entityID: "")
            })
        }
        if let script = states.values.filter({ $0.domain == "script" }).sortedByName().first {
            run.append(Entry(id: "script", symbol: "scroll.fill", color: .teal, title: String(localized: "A script"), example: script.name) {
                .device(entityID: "", service: "script.turn_on", data: [:])
            })
        }
        if !automations.isEmpty {
            run.append(Entry(id: "rule", symbol: "arrow.triangle.branch", color: .purple, title: String(localized: "Another rule"),
                             example: String(localized: "Run it, turn it on or off")) { .device(entityID: "", service: "automation.trigger", data: [:]) })
        }
        var flow: [Entry] = [
            Entry(id: "wait", symbol: "hourglass", color: .gray, title: String(localized: "Wait"),
                  example: String(localized: "5 min before the next step")) { .wait(minutes: 5) },
        ]
        if !notifyServices.isEmpty {
            let service = notifyServices.first { $0.hasPrefix("mobile_app_") } ?? notifyServices[0]
            flow.append(Entry(id: "notify", symbol: "bell.fill", color: .red, title: String(localized: "Send a notification"),
                              example: String(localized: "To \(NotifyTarget.name(service))")) { .notify(service: service, message: "") })
        }
        return [
            CatalogSection(title: String(localized: "Devices"), entries: devices),
            CatalogSection(title: String(localized: "Run"), entries: run),
            CatalogSection(title: String(localized: "Sequence"), entries: flow),
        ].filter { !$0.entries.isEmpty }
    }

    func catalogID(of action: AutomationRule.Action) -> String? {
        switch action {
        case .device(let id, let service, _):
            if service.hasPrefix("script.") || id.hasPrefix("script.") { return "script" }
            if service.hasPrefix("automation.") || id.hasPrefix("automation.") { return "rule" }
            return "device"
        case .roomLights: return "roomLights"
        case .scene: return "scene"
        case .wait: return "wait"
        case .notify: return "notify"
        case .other: return nil
        }
    }
}

/// "mobile_app_iphone_de_theo" → "Iphone De Theo".
enum NotifyTarget {
    static func name(_ service: String) -> String {
        service.replacingOccurrences(of: "mobile_app_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// The catalog as a list of grouped rows; picking one returns its step.
struct StepCatalog<Step>: View {
    let sections: [CatalogSection<Step>]
    let pick: (CatalogEntry<Step>) -> Void

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        Button { pick(entry) } label: { CatalogRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CatalogRow<Step>: View {
    let entry: CatalogEntry<Step>

    var body: some View {
        HStack(spacing: 14) {
            CatalogIcon(symbol: entry.symbol, color: entry.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.roundedBody).foregroundStyle(.primary)
                Text(entry.example).font(.roundedSubheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

struct CatalogIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.14), in: .circle)
    }
}
