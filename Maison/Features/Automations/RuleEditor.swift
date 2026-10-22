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
            dismiss()
        } catch {
            self.error = String(localized: "Couldn’t save the rule. Editing automations needs an administrator account in Home Assistant.")
        }
        isSaving = false
    }

    private func delete() async {
        do {
            try await store.delete(rule)
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
                    Button("Delete", systemImage: "trash", role: .destructive) { remove(step.1) }
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

private struct StepEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let step: EditedStep
    @Binding var rule: AutomationRule

    @State private var trigger = AutomationRule.Trigger.time(at: "19:00:00")
    @State private var condition = AutomationRule.Condition.afterSunset
    @State private var action = AutomationRule.Action.wait(minutes: 5)
    @State private var notifyServices: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .trigger: TriggerFields(trigger: $trigger)
                case .condition: ConditionFields(condition: $condition)
                case .action: ActionFields(action: $action, notifyServices: notifyServices)
                }
                if isExisting {
                    Section {
                        Button("Delete", role: .destructive) {
                            remove()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        apply()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: load)
        .task { notifyServices = await store.notifyServices() }
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
            if case .state(let id, _, _) = trigger { return !id.isEmpty }
            if case .threshold(let id, let above, let below) = trigger { return !id.isEmpty && (above != nil || below != nil) }
            return true
        case .condition:
            if case .state(let id, _) = condition { return !id.isEmpty }
            if case .weekdays(let days) = condition { return !days.isEmpty }
            return true
        case .action:
            if case .device(let id, _, _) = action { return !id.isEmpty }
            if case .scene(let id) = action { return !id.isEmpty }
            if case .notify(let service, let message) = action { return !service.isEmpty && !message.isEmpty }
            return true
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
                Text([entity.name, store.area(of: entity)?.name].compactMap(\.self).joined(separator: " · ")).tag(entity.entityID)
            }
        }
    }
}

private struct TriggerFields: View {
    @Environment(HomeStore.self) private var store
    @Binding var trigger: AutomationRule.Trigger

    enum Kind: Hashable { case time, sun, device, threshold, presence, other }

    var body: some View {
        Section {
            if kind == .other {
                Text("This trigger was set up in Home Assistant. Maison keeps it as it is.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Type", selection: Binding(get: { kind }, set: { setKind($0) })) {
                    Text("At a time").tag(Kind.time)
                    Text("Sunrise or sunset").tag(Kind.sun)
                    Text("A device changes").tag(Kind.device)
                    Text("A measurement crosses a value").tag(Kind.threshold)
                    Text("Arrivals and departures").tag(Kind.presence)
                }
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
            case .threshold(let id, let above, let below):
                EntityPicker(title: "Measurement", entityID: Binding(get: { id }, set: { trigger = .threshold(entityID: $0, above: above, below: below) }),
                             filter: { $0.kind == .sensor && $0.numericState != nil })
                Picker("When it goes", selection: Binding(get: { above != nil }, set: { isAbove in
                    let value = above ?? below
                    trigger = isAbove ? .threshold(entityID: id, above: value, below: nil) : .threshold(entityID: id, above: nil, below: value)
                })) {
                    Text("Above").tag(true)
                    Text("Below").tag(false)
                }
                .pickerStyle(.segmented)
                TextField("Value", value: Binding(get: { above ?? below }, set: { value in
                    trigger = above != nil || below == nil ? .threshold(entityID: id, above: value, below: nil) : .threshold(entityID: id, above: nil, below: value)
                }), format: .number)
                    .keyboardType(.decimalPad)
            case .everyoneLeaves, .someoneArrives:
                Picker("When", selection: Binding(get: { trigger == .everyoneLeaves }, set: { trigger = $0 ? .everyoneLeaves : .someoneArrives })) {
                    Text("Everyone leaves").tag(true)
                    Text("Someone arrives").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            case .other:
                EmptyView()
            }
        } footer: {
            if kind == .presence {
                Text("Uses the people Home Assistant tracks, usually through its companion app.")
            }
        }
    }

    private var kind: Kind {
        switch trigger {
        case .time: .time
        case .sun: .sun
        case .state: .device
        case .threshold: .threshold
        case .everyoneLeaves, .someoneArrives: .presence
        case .other: .other
        }
    }

    private func setKind(_ kind: Kind) {
        guard kind != self.kind else { return }
        switch kind {
        case .time: trigger = .time(at: "19:00:00")
        case .sun: trigger = .sun(.sunset, offset: 0)
        case .device: trigger = .state(entityID: "", to: nil, forMinutes: nil)
        case .threshold: trigger = .threshold(entityID: "", above: 25, below: nil)
        case .presence: trigger = .everyoneLeaves
        case .other: break
        }
    }
}

private struct ConditionFields: View {
    @Environment(HomeStore.self) private var store
    @Binding var condition: AutomationRule.Condition

    enum Kind: Hashable { case sun, presence, time, days, device, other }

    var body: some View {
        Section {
            if kind == .other {
                Text("This condition was set up in Home Assistant. Maison keeps it as it is.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Type", selection: Binding(get: { kind }, set: { setKind($0) })) {
                    Text("Daylight").tag(Kind.sun)
                    Text("Someone at home").tag(Kind.presence)
                    Text("Time of day").tag(Kind.time)
                    Text("Days of the week").tag(Kind.days)
                    Text("A device’s state").tag(Kind.device)
                }
            }
        }
        Section {
            switch condition {
            case .afterSunset, .beforeSunrise:
                Picker("Only", selection: Binding(get: { condition == .afterSunset }, set: { condition = $0 ? .afterSunset : .beforeSunrise })) {
                    Text("After sunset").tag(true)
                    Text("Before sunrise").tag(false)
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
            case .other:
                EmptyView()
            }
        }
    }

    private var kind: Kind {
        switch condition {
        case .afterSunset, .beforeSunrise: .sun
        case .someoneHome, .nobodyHome: .presence
        case .between: .time
        case .weekdays: .days
        case .state: .device
        case .other: .other
        }
    }

    private func setKind(_ kind: Kind) {
        guard kind != self.kind else { return }
        switch kind {
        case .sun: condition = .afterSunset
        case .presence: condition = .someoneHome
        case .time: condition = .between(after: "22:00:00", before: "06:00:00")
        case .days: condition = .weekdays(["mon", "tue", "wed", "thu", "fri"])
        case .device: condition = .state(entityID: "", state: "on")
        case .other: break
        }
    }
}

private struct ActionFields: View {
    @Environment(HomeStore.self) private var store
    @Binding var action: AutomationRule.Action
    let notifyServices: [String]

    enum Kind: Hashable { case device, scene, wait, notify, other }

    var body: some View {
        Section {
            if kind == .other {
                Text("This action was set up in Home Assistant. Maison keeps it as it is.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Type", selection: Binding(get: { kind }, set: { setKind($0) })) {
                    Text("Control a device").tag(Kind.device)
                    Text("Run a scene").tag(Kind.scene)
                    Text("Wait").tag(Kind.wait)
                    Text("Send a notification").tag(Kind.notify)
                }
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
            case .scene(let id):
                EntityPicker(title: "Scene", entityID: Binding(get: { id }, set: { action = .scene(entityID: $0) }),
                             filter: { $0.kind == .scene })
            case .wait(let minutes):
                Stepper(value: Binding(get: { minutes }, set: { action = .wait(minutes: $0) }), in: 1...600) {
                    Text("Wait \(minutes) min")
                }
            case .notify(let service, let message):
                Picker("Send to", selection: Binding(get: { service }, set: { action = .notify(service: $0, message: message) })) {
                    Text("Choose…").tag("")
                    ForEach(notifyServices, id: \.self) { Text($0.replacingOccurrences(of: "mobile_app_", with: "").replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                }
                TextField("Message", text: Binding(get: { message }, set: { action = .notify(service: service, message: $0) }), axis: .vertical)
            case .other:
                EmptyView()
            }
        }
    }

    private var kind: Kind {
        switch action {
        case .device: .device
        case .scene: .scene
        case .wait: .wait
        case .notify: .notify
        case .other: .other
        }
    }

    private func setKind(_ kind: Kind) {
        guard kind != self.kind else { return }
        switch kind {
        case .device: action = .device(entityID: "", service: "", data: [:])
        case .scene: action = .scene(entityID: "")
        case .wait: action = .wait(minutes: 5)
        case .notify: action = .notify(service: notifyServices.first { $0.hasPrefix("mobile_app_") } ?? notifyServices.first ?? "", message: "")
        case .other: break
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
        }
        if service == "climate.set_temperature" {
            Stepper(value: Binding(get: { data["temperature"]?.doubleValue ?? 21 }, set: { value in
                onChange(service, ["temperature": .number(value)])
            }), in: 10...30, step: entity.temperatureStep) {
                Text(EntityState.degrees(data["temperature"]?.doubleValue ?? 21))
            }
        }
    }

    static func services(for entity: EntityState) -> [String] {
        let domain = entity.domain
        switch entity.kind {
        case .light: return ["light.turn_on", "light.turn_off"]
        case .cover: return ["cover.open_cover", "cover.close_cover", "cover.set_cover_position"]
        case .lock: return ["lock.lock", "lock.unlock"]
        case .climate: return ["climate.set_temperature", "climate.turn_off"]
        case .mediaPlayer: return ["media_player.media_play", "media_player.media_pause", "media_player.turn_off"]
        default: return ["\(domain).turn_on", "\(domain).turn_off"]
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
