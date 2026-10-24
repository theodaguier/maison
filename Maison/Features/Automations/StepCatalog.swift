import SwiftUI

/// One type of step a rule can use, as the catalogue shows it: icon, colour, name and an example.
struct StepChoice<Kind: Hashable>: Identifiable {
    let kind: Kind
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let example: LocalizedStringKey
    var id: Kind { kind }
}

struct StepGroup<Kind: Hashable> {
    let title: LocalizedStringKey
    let choices: [StepChoice<Kind>]
}

extension Array {
    func choice<Kind: Hashable>(_ kind: Kind) -> StepChoice<Kind>? where Element == StepGroup<Kind> {
        lazy.flatMap(\.choices).first { $0.kind == kind }
    }
}

// MARK: - Kinds

enum TriggerKind: Hashable {
    case time, sun, every, calendar, device, threshold, tag, serverStarts, household, person

    /// `nil` for a trigger written in Home Assistant that the app keeps as it is.
    init?(_ trigger: AutomationRule.Trigger) {
        switch trigger {
        case .time: self = .time
        case .sun: self = .sun
        case .every: self = .every
        case .calendar: self = .calendar
        case .state: self = .device
        case .threshold: self = .threshold
        case .tag: self = .tag
        case .serverStarts: self = .serverStarts
        case .everyoneLeaves, .someoneArrives: self = .household
        case .person: self = .person
        case .other: return nil
        }
    }

    @MainActor static let groups: [StepGroup<TriggerKind>] = [
        StepGroup(title: "Timing", choices: [
            StepChoice(kind: .time, symbol: "clock.fill", color: .blue, title: "At a time", example: "Every day at 7:30"),
            StepChoice(kind: .sun, symbol: "sunset.fill", color: .orange, title: "Sunrise or sunset", example: "30 min before sunset"),
            StepChoice(kind: .every, symbol: "repeat", color: .blue, title: "At regular intervals", example: "Every 15 minutes"),
            StepChoice(kind: .calendar, symbol: "calendar", color: .red, title: "A calendar event", example: "When “Remote work” starts"),
        ]),
        StepGroup(title: "Home", choices: [
            StepChoice(kind: .device, symbol: "switch.2", color: .teal, title: "A device changes", example: "The front door opens"),
            StepChoice(kind: .threshold, symbol: "thermometer.medium", color: .orange, title: "A measurement crosses a value", example: "Living room above 25°"),
            StepChoice(kind: .tag, symbol: "sensor.tag.radiowaves.forward.fill", color: .green, title: "An NFC tag is scanned", example: "The “Entrance” tag"),
            StepChoice(kind: .serverStarts, symbol: "power", color: .gray, title: "The server starts", example: "After a power cut or an update"),
        ]),
        StepGroup(title: "People", choices: [
            StepChoice(kind: .household, symbol: "person.2.fill", color: .indigo, title: "The household leaves or returns", example: "Everyone leaves, someone arrives"),
            StepChoice(kind: .person, symbol: "figure.walk.arrival", color: .indigo, title: "A person arrives or leaves", example: "Théo gets home"),
        ]),
    ]
}

enum ConditionKind: Hashable {
    case sun, time, days, household, person, device, threshold

    init?(_ condition: AutomationRule.Condition) {
        switch condition {
        case .afterSunset, .beforeSunrise, .daytime, .nighttime: self = .sun
        case .between: self = .time
        case .weekdays: self = .days
        case .someoneHome, .nobodyHome: self = .household
        case .person: self = .person
        case .state: self = .device
        case .threshold: self = .threshold
        case .other: return nil
        }
    }

    @MainActor static let groups: [StepGroup<ConditionKind>] = [
        StepGroup(title: "Timing", choices: [
            StepChoice(kind: .sun, symbol: "sun.horizon.fill", color: .orange, title: "Day or night", example: "Only after sunset"),
            StepChoice(kind: .time, symbol: "clock.fill", color: .blue, title: "Time of day", example: "Between 22:00 and 6:00"),
            StepChoice(kind: .days, symbol: "calendar", color: .red, title: "Days of the week", example: "On weekdays"),
        ]),
        StepGroup(title: "People", choices: [
            StepChoice(kind: .household, symbol: "person.2.fill", color: .indigo, title: "Someone at home", example: "Someone is home"),
            StepChoice(kind: .person, symbol: "person.fill.checkmark", color: .indigo, title: "A specific person", example: "Théo is away"),
        ]),
        StepGroup(title: "Home", choices: [
            StepChoice(kind: .device, symbol: "switch.2", color: .teal, title: "A device’s state", example: "The front door is locked"),
            StepChoice(kind: .threshold, symbol: "gauge.with.dots.needle.50percent", color: .orange, title: "A measurement’s value", example: "Outside below 0°"),
        ]),
    ]
}

enum ActionKind: Hashable {
    case device, lights, scene, script, rule, wait, notify

    init?(_ action: AutomationRule.Action) {
        switch action {
        case .device: self = .device
        case .lights: self = .lights
        case .scene: self = .scene
        case .script: self = .script
        case .rule: self = .rule
        case .wait: self = .wait
        case .notify: self = .notify
        case .other: return nil
        }
    }

    @MainActor static let groups: [StepGroup<ActionKind>] = [
        StepGroup(title: "Devices", choices: [
            StepChoice(kind: .device, symbol: "switch.2", color: .orange, title: "Control a device", example: "Floor lamp · Turn on"),
            StepChoice(kind: .lights, symbol: "lightbulb.2.fill", color: .yellow, title: "Lights in a room", example: "Turn off every light in the bedroom"),
        ]),
        StepGroup(title: "Run", choices: [
            StepChoice(kind: .scene, symbol: "play.fill", color: .orange, title: "A scene", example: "Movie night"),
            StepChoice(kind: .script, symbol: "scroll.fill", color: .teal, title: "A script", example: "Water the garden"),
            StepChoice(kind: .rule, symbol: "arrow.triangle.branch", color: .purple, title: "Another rule", example: "Run it, turn it on or off"),
        ]),
        StepGroup(title: "Flow", choices: [
            StepChoice(kind: .wait, symbol: "hourglass", color: .gray, title: "Wait", example: "5 min before the next step"),
            StepChoice(kind: .notify, symbol: "bell.fill", color: .red, title: "Send a notification", example: "To Théo’s iPhone"),
        ]),
    ]
}

// MARK: - Views

/// The coloured round icon of a kind of step.
struct StepBadge: View {
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

/// Every kind of step, grouped, to pick the one to add.
struct StepCatalog<Kind: Hashable>: View {
    let groups: [StepGroup<Kind>]
    let onPick: (Kind) -> Void

    var body: some View {
        List {
            ForEach(groups.indices, id: \.self) { index in
                Section(groups[index].title) {
                    ForEach(groups[index].choices) { choice in
                        Button {
                            onPick(choice.kind)
                        } label: {
                            HStack(spacing: 12) {
                                StepBadge(symbol: choice.symbol, color: choice.color)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(choice.title).font(.roundedBody).foregroundStyle(.primary)
                                    Text(choice.example).font(.roundedSubheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// The kind of the step being edited, at the top of its form: tapping it switches to another kind.
struct StepKindMenu<Kind: Hashable>: View {
    let groups: [StepGroup<Kind>]
    @Binding var kind: Kind

    var body: some View {
        Menu {
            Picker("Type", selection: $kind) {
                ForEach(groups.indices, id: \.self) { index in
                    Section(groups[index].title) {
                        ForEach(groups[index].choices) { choice in
                            Label(choice.title, systemImage: choice.symbol).tag(choice.kind)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let choice = groups.choice(kind) {
                    StepBadge(symbol: choice.symbol, color: choice.color)
                    Text(choice.title).font(.roundedBody).foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                Text("Change").font(.roundedBody).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        // A tick when the kind of step changes.
        .sensoryFeedback(.selection, trigger: kind)
    }
}
