import SwiftUI

/// Creates or edits a rule: name, then WHEN / IF / THEN. Saved on the server, so it runs without the iPhone
/// and every member of the household sees it.
struct RuleEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutomationRule
    let isNew: Bool
    /// Set when the rule was suggested from a request: shows the request and what to check before saving.
    var proposal: RuleProposal?
    var onRephrase: () -> Void = {}

    @State private var editing: EditedStep?
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmsDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let proposal {
                        RequestCard(request: proposal.request, onRephrase: onRephrase)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.roundedFootnote).foregroundStyle(.tertiary)
                        TextField("Evening Lights", text: $rule.name)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .focused($nameFocused)
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 0) {
                        section(title: "WHEN", color: .blue, add: "Add a Trigger", target: .trigger(nil),
                                steps: rule.triggers.indices.map { (store.describe(rule.triggers[$0]), EditedStep.trigger($0)) })
                        section(title: "IF", color: .purple, optional: true, add: "Add a Condition", target: .condition(nil),
                                steps: rule.conditions.indices.map { (store.describe(rule.conditions[$0]), EditedStep.condition($0)) })
                        section(title: "THEN", color: .orange, add: "Add an Action", target: .action(nil),
                                steps: rule.actions.indices.map { (store.describe(rule.actions[$0]), EditedStep.action($0)) })
                    }
                    .padding(16)
                    .cardStyle()

                    if let proposal {
                        ForEach(proposal.notes, id: \.self) { CheckNote(text: $0) }
                        let leftOut = proposal.unsupported + proposal.unmatched
                        if !leftOut.isEmpty {
                            CheckNote(text: String(localized: "Left out: \(leftOut.map { "“\($0)”" }.formatted(.list(type: .and)))."))
                        }
                    }

                    Label(proposal == nil ? LocalizedStringKey("Saved on your server and shared with the household")
                                           : LocalizedStringKey("Nothing is saved until you confirm. Then the rule runs on your server, like the others."),
                          systemImage: "server.rack")
                        .labelStyle(.compact)
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)

                    if let error {
                        Text(error)
                            .font(.roundedFootnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }

                    if !isNew {
                        WideButton(title: "Delete Rule", style: .destructive) { confirmsDelete = true }
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(proposal != nil ? "Suggested Rule" : isNew ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(item: $editing) { step in
                StepEditor(step: step, rule: $rule)
            }
            .confirmationDialog("Delete this rule?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete Rule", role: .destructive) { Task { await delete() } }
            }
            .onAppear { if isNew, proposal == nil { nameFocused = true } }
        }
        .errorFeedback(error)
    }

    private var canSave: Bool {
        !rule.name.trimmingCharacters(in: .whitespaces).isEmpty && !rule.triggers.isEmpty && !rule.actions.isEmpty
    }

    private func save() async {
        isSaving = true
        error = nil
        do {
            try await store.save(rule)
            Haptics.success()
            dismiss()
        } catch {
            self.error = String(localized: "Couldn’t save the rule. Editing automations needs an administrator account in Home Assistant.")
        }
        isSaving = false
    }

    private func delete() async {
        do {
            try await store.delete(rule)
            Haptics.impact(.medium)
            dismiss()
        } catch {
            self.error = String(localized: "Couldn’t delete the rule.")
        }
    }

    // MARK: Sections

    private func section(title: LocalizedStringKey, color: Color, optional: Bool = false, add: LocalizedStringKey,
                         target: EditedStep, steps: [(StepDescription, EditedStep)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12), in: .capsule)
                if optional {
                    Text("Optional").font(.roundedFootnote).foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 8)
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                Button {
                    editing = step.1
                } label: {
                    RuleStepRow(description: step.0, showsChevron: true)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        remove(step.1)
                        Haptics.impact(.medium)
                    }
                }
            }
            Button {
                editing = target
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .overlay { Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                    Text(add).font(.roundedBody)
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 10)
    }

    private func remove(_ step: EditedStep) {
        switch step {
        case .trigger(let index?): rule.triggers.remove(at: index)
        case .condition(let index?): rule.conditions.remove(at: index)
        case .action(let index?): rule.actions.remove(at: index)
        default: break
        }
    }
}

/// Which step is being edited; `nil` for a new one.
enum EditedStep: Identifiable, Hashable {
    case trigger(Int?)
    case condition(Int?)
    case action(Int?)

    var id: String {
        switch self {
        case .trigger(let index): "t\(index ?? -1)"
        case .condition(let index): "c\(index ?? -1)"
        case .action(let index): "a\(index ?? -1)"
        }
    }
}

struct RuleStepRow: View {
    let description: StepDescription
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: description.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(description.color)
                .frame(width: 26, height: 26)
                .background(description.color.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(description.title).font(.roundedBody).foregroundStyle(.primary)
                if let detail = description.detail {
                    Text(detail).font(.roundedSubheadline).foregroundStyle(.secondary)
                }
            }
            .lineLimit(2)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

// MARK: - Step editor

/// A new step starts on the catalogue of every kind, then opens its settings; an existing step opens on its settings.
private struct StepEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let step: EditedStep
    @Binding var rule: AutomationRule

    @State private var trigger = AutomationRule.Trigger.time(at: "19:00:00")
    @State private var condition = AutomationRule.Condition.afterSunset
    @State private var action = AutomationRule.Action.wait(minutes: 5)
    @State private var notifyServices: [String] = []
    @State private var tags: [(id: String, name: String)] = []
    @State private var path: [Page] = []

    private enum Page: Hashable { case settings }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isExisting {
                    settings
                } else {
                    catalog
                        .navigationDestination(for: Page.self) { _ in settings }
                }
            }
        }
        .presentationDetents(isExisting ? [.medium, .large] : [.large])
        .onAppear(perform: load)
        .task {
            notifyServices = await store.notifyServices()
            tags = await store.tags()
        }
    }

    // MARK: Catalogue

    @ViewBuilder private var catalog: some View {
        Group {
            switch step {
            case .trigger: StepCatalog(groups: TriggerKind.groups) { trigger = TriggerFields.initial($0); open() }
            case .condition: StepCatalog(groups: ConditionKind.groups) { condition = ConditionFields.initial($0); open() }
            case .action:
                StepCatalog(groups: ActionKind.groups) { action = ActionFields.initial($0, notifyServices: notifyServices); open() }
            }
        }
        .navigationTitle(addTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { dismiss() }
            }
        }
    }

    private func open() {
        Haptics.selection()
        path.append(.settings)
    }

    private var addTitle: LocalizedStringKey {
        switch step {
        case .trigger: "Add a Trigger"
        case .condition: "Add a Condition"
        case .action: "Add an Action"
        }
    }

    // MARK: Settings

    private var settings: some View {
        Form {
            switch step {
            case .trigger: TriggerFields(trigger: $trigger, tags: tags)
            case .condition: ConditionFields(condition: $condition)
            case .action: ActionFields(action: $action, notifyServices: notifyServices)
            }
            if isExisting {
                Section {
                    Button("Delete", role: .destructive) {
                        remove()
                        Haptics.impact(.medium)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isExisting {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    apply()
                    Haptics.impact()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .trigger: "When"
        case .condition: "If"
        case .action: "Then"
        }
    }

    private var isExisting: Bool {
        switch step {
        case .trigger(let index), .condition(let index), .action(let index): index != nil
        }
    }

    private var isValid: Bool {
        switch step {
        case .trigger:
            switch trigger {
            case .state(let id, _, _), .calendar(let id, _, _), .person(let id, _), .tag(let id): return !id.isEmpty
            case .threshold(let id, let above, let below): return !id.isEmpty && (above != nil || below != nil)
            default: return true
            }
        case .condition:
            switch condition {
            case .state(let id, _), .person(let id, _): return !id.isEmpty
            case .threshold(let id, let above, let below): return !id.isEmpty && (above != nil || below != nil)
            case .weekdays(let days): return !days.isEmpty
            default: return true
            }
        case .action:
            switch action {
            case .device(let id, _, _), .scene(let id), .script(let id), .rule(let id, _): return !id.isEmpty
            case .notify(let service, let message): return !service.isEmpty && !message.isEmpty
            default: return true
            }
        }
    }

    private func load() {
        switch step {
        case .trigger(let index?): trigger = rule.triggers[index]
        case .condition(let index?): condition = rule.conditions[index]
        case .action(let index?): action = rule.actions[index]
        default: break
        }
    }

    private func apply() {
        switch step {
        case .trigger(let index): if let index { rule.triggers[index] = trigger } else { rule.triggers.append(trigger) }
        case .condition(let index): if let index { rule.conditions[index] = condition } else { rule.conditions.append(condition) }
        case .action(let index): if let index { rule.actions[index] = action } else { rule.actions.append(action) }
        }
    }

    private func remove() {
        switch step {
        case .trigger(let index?): rule.triggers.remove(at: index)
        case .condition(let index?): rule.conditions.remove(at: index)
        case .action(let index?): rule.actions.remove(at: index)
        default: break
        }
    }
}

/// Lists devices by name for pickers, with their room.
private struct EntityPicker: View {
    @Environment(HomeStore.self) private var store
    let title: LocalizedStringKey
    @Binding var entityID: String
    let filter: (EntityState) -> Bool

    var body: some View {
        Picker(title, selection: $entityID) {
            Text("Choose…").tag("")
            ForEach(store.states.values.filter(filter).sortedByName()) { entity in
                Text([entity.name, store.area(of: entity)?.name].compactMap { $0 }.joined(separator: " · ")).tag(entity.entityID)
            }
        }
    }
}

/// Above or below a value, for a measurement.
private struct ThresholdFields: View {
    let above: Double?
    let below: Double?
    let onChange: (Double?, Double?) -> Void

    var body: some View {
        Picker("When it goes", selection: Binding(get: { above != nil }, set: { isAbove in
            let value = above ?? below
            isAbove ? onChange(value, nil) : onChange(nil, value)
        })) {
            Text("Above").tag(true)
            Text("Below").tag(false)
        }
        .pickerStyle(.segmented)
        TextField("Value", value: Binding(get: { above ?? below }, set: { value in
            above != nil || below == nil ? onChange(value, nil) : onChange(nil, value)
        }), format: .number)
        .keyboardType(.decimalPad)
    }
}

private struct TriggerFields: View {
    @Environment(HomeStore.self) private var store
    @Binding var trigger: AutomationRule.Trigger
    let tags: [(id: String, name: String)]

    static let intervals = [5, 10, 15, 30, 60, 120, 180, 360, 720]

    static func initial(_ kind: TriggerKind) -> AutomationRule.Trigger {
        switch kind {
        case .time: .time(at: "19:00:00")
        case .sun: .sun(.sunset, offset: 0)
        case .every: .every(minutes: 15)
        case .calendar: .calendar(entityID: "", start: true, offset: 0)
        case .device: .state(entityID: "", to: nil, forMinutes: nil)
        case .threshold: .threshold(entityID: "", above: 25, below: nil)
        case .tag: .tag(id: "")
        case .serverStarts: .serverStarts
        case .household: .everyoneLeaves
        case .person: .person(entityID: "", arrives: true)
        }
    }

    var body: some View {
        Section {
            if let kind = TriggerKind(trigger) {
                StepKindMenu(groups: TriggerKind.groups, kind: Binding(get: { kind }, set: { if $0 != kind { trigger = Self.initial($0) } }))
            } else {
                Text("This trigger was set up in Home Assistant. Maison keeps it as it is.")
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            switch trigger {
            case .time(let at):
                DatePicker("Time", selection: Binding(get: { RuleTime.date(at) }, set: { trigger = .time(at: RuleTime.text($0)) }),
                           displayedComponents: .hourAndMinute)
            case .sun(let event, let offset):
                Picker("Event", selection: Binding(get: { event }, set: { trigger = .sun($0, offset: offset) })) {
                    Text("Sunrise").tag(AutomationRule.SunEvent.sunrise)
                    Text("Sunset").tag(AutomationRule.SunEvent.sunset)
                }
                .pickerStyle(.segmented)
                Stepper(value: Binding(get: { offset }, set: { trigger = .sun(event, offset: $0) }), in: -180...180, step: 15) {
                    Text(RuleTime.sunText(event, offset: offset))
                }
                .stepFeedback(offset)
            case .every(let minutes):
                Picker("Every", selection: Binding(get: { minutes }, set: { trigger = .every(minutes: $0) })) {
                    ForEach(Self.intervals.contains(minutes) ? Self.intervals : [minutes] + Self.intervals, id: \.self) {
                        Text(RuleTime.everyText($0)).tag($0)
                    }
                }
            case .calendar(let id, let start, let offset):
                EntityPicker(title: "Calendar", entityID: Binding(get: { id }, set: { trigger = .calendar(entityID: $0, start: start, offset: offset) }),
                             filter: { $0.domain == "calendar" })
                Picker("Moment", selection: Binding(get: { start }, set: { trigger = .calendar(entityID: id, start: $0, offset: offset) })) {
                    Text("When it starts").tag(true)
                    Text("When it ends").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper(value: Binding(get: { offset }, set: { trigger = .calendar(entityID: id, start: start, offset: $0) }), in: -240...240, step: 5) {
                    Text(RuleTime.calendarText(start: start, offset: offset))
                }
                .stepFeedback(offset)
            case .state(let id, let to, let forMinutes):
                EntityPicker(title: "Device", entityID: Binding(get: { id }, set: { trigger = .state(entityID: $0, to: nil, forMinutes: forMinutes) }),
                             filter: { [.light, .switch, .cover, .lock, .binarySensor, .mediaPlayer, .fan, .climate].contains($0.kind) })
                if let entity = store.states[id] {
                    Picker("Becomes", selection: Binding(get: { to ?? "" }, set: { trigger = .state(entityID: id, to: $0.isEmpty ? nil : $0, forMinutes: forMinutes) })) {
                        Text("Any change").tag("")
                        ForEach(StateChoices.states(for: entity), id: \.self) { state in
                            Text(store.stateName(state, of: id).capitalized).tag(state)
                        }
                    }
                }
                Stepper(value: Binding(get: { forMinutes ?? 0 }, set: { trigger = .state(entityID: id, to: to, forMinutes: $0 == 0 ? nil : $0) }),
                        in: 0...240, step: 5) {
                    Text(forMinutes.map { String(localized: "For \($0) min") } ?? String(localized: "Right away"))
                }
                .stepFeedback(forMinutes ?? 0)
            case .threshold(let id, let above, let below):
                EntityPicker(title: "Measurement", entityID: Binding(get: { id }, set: { trigger = .threshold(entityID: $0, above: above, below: below) }),
                             filter: { $0.kind == .sensor && $0.numericState != nil })
                ThresholdFields(above: above, below: below) { trigger = .threshold(entityID: id, above: $0, below: $1) }
            case .tag(let id):
                Picker("Tag", selection: Binding(get: { id }, set: { trigger = .tag(id: $0) })) {
                    Text("Choose…").tag("")
                    ForEach(tags, id: \.id) { Text($0.name).tag($0.id) }
                }
            case .serverStarts:
                Text("When Home Assistant starts")
            case .everyoneLeaves, .someoneArrives:
                Picker("When", selection: Binding(get: { trigger == .everyoneLeaves }, set: { trigger = $0 ? .everyoneLeaves : .someoneArrives })) {
                    Text("Everyone leaves").tag(true)
                    Text("Someone arrives").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            case .person(let id, let arrives):
                EntityPicker(title: "Person", entityID: Binding(get: { id }, set: { trigger = .person(entityID: $0, arrives: arrives) }),
                             filter: { $0.domain == "person" })
                Picker("When", selection: Binding(get: { arrives }, set: { trigger = .person(entityID: id, arrives: $0) })) {
                    Text("Arrives home").tag(true)
                    Text("Leaves home").tag(false)
                }
                .pickerStyle(.segmented)
            case .other:
                EmptyView()
            }
        } footer: {
            switch TriggerKind(trigger) {
            case .household?, .person?: Text("Uses the people Home Assistant tracks, usually through its companion app.")
            case .calendar?: Text("Uses the calendars connected to Home Assistant: work, family, holidays…")
            case .tag?: Text("Tags are written and named from the Home Assistant companion app.")
            case .serverStarts?: Text("Useful to put things back in order after a power cut or an update.")
            default: EmptyView()
            }
        }
    }
}

private struct ConditionFields: View {
    @Environment(HomeStore.self) private var store
    @Binding var condition: AutomationRule.Condition

    static func initial(_ kind: ConditionKind) -> AutomationRule.Condition {
        switch kind {
        case .sun: .afterSunset
        case .time: .between(after: "22:00:00", before: "06:00:00")
        case .days: .weekdays(["mon", "tue", "wed", "thu", "fri"])
        case .household: .someoneHome
        case .person: .person(entityID: "", isHome: true)
        case .device: .state(entityID: "", state: "on")
        case .threshold: .threshold(entityID: "", above: 25, below: nil)
        }
    }

    var body: some View {
        Section {
            if let kind = ConditionKind(condition) {
                StepKindMenu(groups: ConditionKind.groups, kind: Binding(get: { kind }, set: { if $0 != kind { condition = Self.initial($0) } }))
            } else {
                Text("This condition was set up in Home Assistant. Maison keeps it as it is.")
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            switch condition {
            case .afterSunset, .beforeSunrise, .daytime, .nighttime:
                let options: [(AutomationRule.Condition, LocalizedStringKey)] = [
                    (.afterSunset, "After sunset"), (.beforeSunrise, "Before sunrise"), (.daytime, "During the day"), (.nighttime, "At night"),
                ]
                Picker("Only", selection: Binding(get: { options.firstIndex { $0.0 == condition } ?? 0 }, set: { condition = options[$0].0 })) {
                    ForEach(options.indices, id: \.self) { Text(options[$0].1).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            case .someoneHome, .nobodyHome:
                Picker("Only if", selection: Binding(get: { condition == .someoneHome }, set: { condition = $0 ? .someoneHome : .nobodyHome })) {
                    Text("Someone is home").tag(true)
                    Text("Nobody is home").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            case .person(let id, let isHome):
                EntityPicker(title: "Person", entityID: Binding(get: { id }, set: { condition = .person(entityID: $0, isHome: isHome) }),
                             filter: { $0.domain == "person" })
                Picker("Is", selection: Binding(get: { isHome }, set: { condition = .person(entityID: id, isHome: $0) })) {
                    Text("At home").tag(true)
                    Text("Away").tag(false)
                }
                .pickerStyle(.segmented)
            case .between(let after, let before):
                DatePicker("From", selection: Binding(get: { RuleTime.date(after) }, set: { condition = .between(after: RuleTime.text($0), before: before) }),
                           displayedComponents: .hourAndMinute)
                DatePicker("To", selection: Binding(get: { RuleTime.date(before) }, set: { condition = .between(after: after, before: RuleTime.text($0)) }),
                           displayedComponents: .hourAndMinute)
            case .weekdays(let days):
                ForEach(RuleTime.weekdayKeys, id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[(RuleTime.weekdayKeys.firstIndex(of: day)! + 1) % 7].capitalized, isOn: Binding(
                        get: { days.contains(day) },
                        set: { on in condition = .weekdays(on ? days + [day] : days.filter { $0 != day }) }
                    ))
                    .sensoryFeedback(.selection, trigger: days.contains(day))
                }
            case .state(let id, let state):
                EntityPicker(title: "Device", entityID: Binding(get: { id }, set: { condition = .state(entityID: $0, state: state) }),
                             filter: { [.light, .switch, .cover, .lock, .binarySensor, .mediaPlayer, .fan, .climate].contains($0.kind) })
                if let entity = store.states[id] {
                    Picker("Is", selection: Binding(get: { state }, set: { condition = .state(entityID: id, state: $0) })) {
                        ForEach(StateChoices.states(for: entity), id: \.self) { value in
                            Text(store.stateName(value, of: id).capitalized).tag(value)
                        }
                    }
                }
            case .threshold(let id, let above, let below):
                EntityPicker(title: "Measurement", entityID: Binding(get: { id }, set: { condition = .threshold(entityID: $0, above: above, below: below) }),
                             filter: { $0.kind == .sensor && $0.numericState != nil })
                ThresholdFields(above: above, below: below) { condition = .threshold(entityID: id, above: $0, below: $1) }
            case .other:
                EmptyView()
            }
        }
    }
}

private struct ActionFields: View {
    @Environment(HomeStore.self) private var store
    @Binding var action: AutomationRule.Action
    let notifyServices: [String]

    static func initial(_ kind: ActionKind, notifyServices: [String]) -> AutomationRule.Action {
        switch kind {
        case .device: .device(entityID: "", service: "", data: [:])
        case .lights: .lights(areaID: nil, on: false)
        case .scene: .scene(entityID: "")
        case .script: .script(entityID: "")
        case .rule: .rule(entityID: "", command: .trigger)
        case .wait: .wait(minutes: 5)
        case .notify: .notify(service: notifyServices.first { $0.hasPrefix("mobile_app_") } ?? notifyServices.first ?? "", message: "")
        }
    }

    var body: some View {
        Section {
            if let kind = ActionKind(action) {
                StepKindMenu(groups: ActionKind.groups, kind: Binding(get: { kind }, set: {
                    if $0 != kind { action = Self.initial($0, notifyServices: notifyServices) }
                }))
            } else {
                Text("This action was set up in Home Assistant. Maison keeps it as it is.")
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            switch action {
            case .device(let id, let service, let data):
                EntityPicker(title: "Device", entityID: Binding(get: { id }, set: { newID in
                    let kind = store.states[newID]?.kind
                    action = .device(entityID: newID, service: DeviceChoices.defaultService(for: kind, domain: String(newID.prefix { $0 != "." })), data: [:])
                }), filter: { [.light, .switch, .cover, .lock, .mediaPlayer, .fan, .climate].contains($0.kind) })
                if let entity = store.states[id] {
                    DeviceChoices(entity: entity, service: service, data: data) { action = .device(entityID: id, service: $0, data: $1) }
                }
            case .lights(let areaID, let on):
                Picker("Lights", selection: Binding(get: { on }, set: { action = .lights(areaID: areaID, on: $0) })) {
                    Text("Turn on").tag(true)
                    Text("Turn off").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("Where", selection: Binding(get: { areaID ?? "" }, set: { action = .lights(areaID: $0.isEmpty ? nil : $0, on: on) })) {
                    Text("Whole home").tag("")
                    ForEach(store.rooms) { Text($0.name).tag($0.id) }
                }
            case .scene(let id):
                EntityPicker(title: "Scene", entityID: Binding(get: { id }, set: { action = .scene(entityID: $0) }),
                             filter: { $0.kind == .scene })
            case .script(let id):
                EntityPicker(title: "Script", entityID: Binding(get: { id }, set: { action = .script(entityID: $0) }),
                             filter: { $0.kind == .script })
            case .rule(let id, let command):
                EntityPicker(title: "Rule", entityID: Binding(get: { id }, set: { action = .rule(entityID: $0, command: command) }),
                             filter: { $0.kind == .automation })
                Picker("Do", selection: Binding(get: { command }, set: { action = .rule(entityID: id, command: $0) })) {
                    Text("Run it").tag(AutomationRule.RuleCommand.trigger)
                    Text("Turn it on").tag(AutomationRule.RuleCommand.turnOn)
                    Text("Turn it off").tag(AutomationRule.RuleCommand.turnOff)
                }
            case .wait(let minutes):
                Stepper(value: Binding(get: { minutes }, set: { action = .wait(minutes: $0) }), in: 1...600) {
                    Text("Wait \(minutes) min")
                }
                .stepFeedback(minutes)
            case .notify(let service, let message):
                Picker("Send to", selection: Binding(get: { service }, set: { action = .notify(service: $0, message: message) })) {
                    Text("Choose…").tag("")
                    ForEach(notifyServices, id: \.self) { Text($0.replacingOccurrences(of: "mobile_app_", with: "").replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                }
                TextField("Message", text: Binding(get: { message }, set: { action = .notify(service: service, message: $0) }), axis: .vertical)
            case .other:
                EmptyView()
            }
        } footer: {
            if case .rule(_, .trigger) = action {
                Text("Runs its actions right away, without checking its conditions.")
            }
        }
    }
}

/// What to do with the chosen device: depends on its type.
private struct DeviceChoices: View {
    let entity: EntityState
    let service: String
    let data: [String: JSONValue]
    let onChange: (String, [String: JSONValue]) -> Void

    var body: some View {
        Picker("Action", selection: Binding(get: { service }, set: { onChange($0, $0 == service ? data : [:]) })) {
            ForEach(Self.services(for: entity), id: \.self) { service in
                Text(Self.title(service)).tag(service)
            }
        }
        if service == "light.turn_on" {
            Stepper(value: Binding(get: { Int(data["brightness_pct"]?.doubleValue ?? 100) }, set: { value in
                var data = data
                data["brightness_pct"] = .number(Double(value))
                onChange(service, data)
            }), in: 5...100, step: 5) {
                Text("Brightness \(Int(data["brightness_pct"]?.doubleValue ?? 100)) %")
            }
            .stepFeedback(Int(data["brightness_pct"]?.doubleValue ?? 100))
            if entity.attributes["supported_color_modes"]?.arrayValue?.contains(.string("color_temp")) == true {
                Picker("White", selection: Binding(get: { data["color_temp_kelvin"]?.doubleValue ?? 0 }, set: { kelvin in
                    var data = data
                    data["color_temp_kelvin"] = kelvin == 0 ? nil : .number(kelvin)
                    onChange(service, data)
                })) {
                    Text("Unchanged").tag(0.0)
                    Text(RuleTime.whiteName(2700).capitalized).tag(2700.0)
                    Text(RuleTime.whiteName(4000).capitalized).tag(4000.0)
                    Text(RuleTime.whiteName(5500).capitalized).tag(5500.0)
                }
            }
        }
        if service == "cover.set_cover_position" {
            Stepper(value: Binding(get: { Int(data["position"]?.doubleValue ?? 50) }, set: { value in
                onChange(service, ["position": .number(Double(value))])
            }), in: 0...100, step: 5) {
                Text("Open \(Int(data["position"]?.doubleValue ?? 50)) %")
            }
            .stepFeedback(Int(data["position"]?.doubleValue ?? 50))
        }
        if service == "climate.set_temperature" {
            Stepper(value: Binding(get: { data["temperature"]?.doubleValue ?? 21 }, set: { value in
                onChange(service, ["temperature": .number(value)])
            }), in: 10...30, step: entity.temperatureStep) {
                Text(EntityState.degrees(data["temperature"]?.doubleValue ?? 21))
            }
            .stepFeedback(data["temperature"]?.doubleValue ?? 21)
        }
        if service == "media_player.volume_set" {
            Stepper(value: Binding(get: { Int((data["volume_level"]?.doubleValue ?? 0.3) * 100) }, set: { value in
                onChange(service, ["volume_level": .number(Double(value) / 100)])
            }), in: 0...100, step: 5) {
                Text("Volume \(Int((data["volume_level"]?.doubleValue ?? 0.3) * 100)) %")
            }
            .stepFeedback(Int((data["volume_level"]?.doubleValue ?? 0.3) * 100))
        }
        if service == "fan.set_percentage" {
            Stepper(value: Binding(get: { Int(data["percentage"]?.doubleValue ?? 50) }, set: { value in
                onChange(service, ["percentage": .number(Double(value))])
            }), in: 0...100, step: 10) {
                Text("Speed \(Int(data["percentage"]?.doubleValue ?? 50)) %")
            }
            .stepFeedback(Int(data["percentage"]?.doubleValue ?? 50))
        }
    }

    static func services(for entity: EntityState) -> [String] {
        let domain = entity.domain
        switch entity.kind {
        case .light: return ["light.turn_on", "light.turn_off", "light.toggle"]
        case .cover: return ["cover.open_cover", "cover.close_cover", "cover.stop_cover", "cover.set_cover_position"]
        case .lock: return ["lock.lock", "lock.unlock"]
        case .climate: return ["climate.set_temperature", "climate.turn_off"]
        case .mediaPlayer: return ["media_player.media_play", "media_player.media_pause", "media_player.volume_set", "media_player.turn_off"]
        case .fan: return ["fan.turn_on", "fan.turn_off", "fan.set_percentage", "fan.toggle"]
        default: return ["\(domain).turn_on", "\(domain).turn_off", "\(domain).toggle"]
        }
    }

    static func defaultService(for kind: DeviceKind?, domain: String) -> String {
        switch kind {
        case .cover: "cover.close_cover"
        case .lock: "lock.lock"
        case .climate: "climate.set_temperature"
        case .mediaPlayer: "media_player.media_pause"
        default: "\(domain).turn_on"
        }
    }

    static func title(_ service: String) -> String {
        switch service.split(separator: ".").last ?? "" {
        case "turn_on": String(localized: "Turn on")
        case "turn_off": String(localized: "Turn off")
        case "toggle": String(localized: "Toggle")
        case "stop_cover": String(localized: "Stop")
        case "volume_set": String(localized: "Set volume")
        case "set_percentage": String(localized: "Set speed")
        case "open_cover": String(localized: "action.open", defaultValue: "Open")
        case "close_cover": String(localized: "Close")
        case "set_cover_position": String(localized: "Set position")
        case "lock": String(localized: "Lock")
        case "unlock": String(localized: "Unlock")
        case "set_temperature": String(localized: "Set temperature")
        case "media_play": String(localized: "Play")
        case "media_pause": String(localized: "Pause")
        default: service
        }
    }
}

/// The states a trigger or condition can wait for, by device type.
enum StateChoices {
    static func states(for entity: EntityState) -> [String] {
        switch entity.kind {
        case .lock: ["locked", "unlocked"]
        case .cover: ["open", "closed"]
        case .mediaPlayer: ["playing", "paused", "off"]
        case .climate: (entity.attributes["hvac_modes"]?.arrayValue?.compactMap(\.stringValue)) ?? ["off", "heat", "cool"]
        default: ["on", "off"]
        }
    }
}
