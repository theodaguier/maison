import SwiftUI

struct AutomationsView: View {
    @Environment(HomeStore.self) private var store
    @State private var filter: Filter = .all
    @State private var rules: [String: AutomationRule] = [:]
    @State private var runs: [AutomationRun] = []
    @State private var editor: EditorTarget?
    @State private var describes = false

    enum Filter: Hashable { case all, enabled, disabled }

    struct EditorTarget: Identifiable {
        let rule: AutomationRule
        let isNew: Bool
        var id: String { rule.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.automations.isEmpty {
                    ContentUnavailableView {
                        Label("No Rules", systemImage: "clock")
                    } description: {
                        Text("Rules run in the home, even when your iPhone is off.")
                    } actions: {
                        Button("New Rule") { editor = EditorTarget(rule: .new(), isNew: true) }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            PillPicker(options: [(.all, "All", nil), (.enabled, "Enabled", nil), (.disabled, "Disabled", nil)], selection: $filter)
                            RunsTodayCard(automations: store.automations, runs: runs)
                            HStack(alignment: .firstTextBaseline) {
                                Text("Rules").font(.roundedTitle3)
                                Spacer()
                                Text("Run by the home")
                                    .font(.roundedFootnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 10)
                            ForEach(filtered) { automation in
                                let id = automation.attributes["id"]?.stringValue
                                AutomationCard(
                                    automation: automation,
                                    rule: id.flatMap { rules[$0] },
                                    runsToday: runs.filter { $0.automationID == id && $0.didRun && Calendar.current.isDateInToday($0.start) }
                                ) {
                                    if let rule = id.flatMap({ rules[$0] }) { editor = EditorTarget(rule: rule, isNew: false) }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.bottom, 24)
                    }
                    .background(Theme.background)
                    .scrollEdgeEffectStyle(.hard, for: .top)
                }
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IntelligenceButton("Describe a Rule") { describes = true }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Rule", systemImage: "plus") {
                        editor = EditorTarget(rule: .new(), isNew: true)
                    }
                }
            }
            .sheet(item: $editor, onDismiss: { Task { await load() } }) { target in
                RuleEditor(rule: target.rule, isNew: target.isNew)
            }
            .sheet(isPresented: $describes, onDismiss: { Task { await load() } }) {
                DescribeRuleView()
            }
            .task(id: store.automations.map(\.entityID)) {
                await load()
                #if DEBUG
                // `-rule lumieres_du_soir` opens a rule at launch, to check its design; `-rule offpeak` the one a finding proposes.
                guard editor == nil, let id = UserDefaults.standard.string(forKey: "rule") else { return }
                if id == "offpeak", let rule = await store.findings().first?.rule {
                    ProposedRules.add(rule.id)
                    editor = EditorTarget(rule: rule, isNew: false)
                } else if let rule = rules[id] {
                    editor = EditorTarget(rule: rule, isNew: false)
                }
                #endif
            }
            .refreshable { await load() }
        }
        .trackScreen(.automations)
    }

    private func load() async {
        runs = await store.automationRuns()
        var loaded: [String: AutomationRule] = [:]
        for automation in store.automations {
            if let rule = try? await store.rule(for: automation) { loaded[rule.id] = rule }
        }
        rules = loaded
    }

    private var filtered: [EntityState] {
        switch filter {
        case .all: store.automations
        case .enabled: store.automations.filter { $0.state == "on" }
        case .disabled: store.automations.filter { $0.state != "on" }
        }
    }
}

extension EntityState {
    var lastTriggered: Date? {
        attributes["last_triggered"]?.stringValue.flatMap(EntityState.parseDate)
    }
}

/// How many rules ran today, whether they all went well, with a bar per hour.
private struct RunsTodayCard: View {
    let automations: [EntityState]
    let runs: [AutomationRun]

    var body: some View {
        let today = runs.filter { $0.didRun && Calendar.current.isDateInToday($0.start) }
        let failed = today.filter(\.failed).count
        let perHour = Dictionary(grouping: today) { Calendar.current.component(.hour, from: $0.start) }.mapValues(\.count)
        let peak = max(perHour.values.max() ?? 1, 1)
        let enabled = automations.filter { $0.state == "on" }.count

        VStack(alignment: .leading, spacing: 0) {
            Label("Runs Today", systemImage: "bolt.fill")
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 12)
            Theme.separator.frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    NumberLabel(value: "\(today.count)", unit: today.count == 1 ? String(localized: "time") : String(localized: "times"), size: .xLarge)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if !today.isEmpty {
                            Text(failed == 0 ? String(localized: "All succeeded") : String(localized: "\(failed) failed"))
                                .font(.roundedHeadline)
                                .foregroundStyle(failed == 0 ? .green : .red)
                        }
                        Text("\(enabled) of \(automations.count) rules enabled")
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        let count = perHour[hour] ?? 0
                        Capsule()
                            .fill(count > 0 ? Color.indigo : Theme.gaugeTrack)
                            .frame(width: 6, height: count > 0 ? 14 + 20 * CGFloat(count) / CGFloat(peak) : 6)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 34, alignment: .bottom)
                HStack {
                    Text("0 h"); Spacer(); Text("6 h"); Spacer(); Text("12 h"); Spacer(); Text("18 h"); Spacer(); Text("24 h")
                }
                .font(.roundedFootnote)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .cardStyle()
    }
}

private struct AutomationCard: View {
    @Environment(HomeStore.self) private var store
    let automation: EntityState
    let rule: AutomationRule?
    let runsToday: [AutomationRun]
    let onOpen: () -> Void
    @State private var disabledBy: String?

    var body: some View {
        let isOn = automation.state == "on"
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    if let trigger = rule?.triggers.first.map(store.describe) {
                        Label {
                            Text(trigger.title).lineLimit(1)
                        } icon: {
                            Image(systemName: trigger.symbol).foregroundStyle(isOn ? trigger.color : Color.secondary)
                        }
                        .labelStyle(.compact)
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { isOn },
                        set: { on in Task { await store.call("automation", on ? "turn_on" : "turn_off", on: automation) } }
                    ))
                    .labelsHidden()
                    .tint(.green)
                }
                Text(automation.name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
                    .lineLimit(2)
                if let rule {
                    Text(store.summary(of: rule))
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Theme.separator.frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "power")
                    .foregroundStyle(isOn ? Color.green : Color.secondary)
                Text(footer)
                    .foregroundStyle(.secondary)
                Spacer()
                if rule != nil {
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                }
            }
            .font(.roundedFootnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .cardStyle()
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Run Now", systemImage: "play.fill") {
                Task { await store.call("automation", "trigger", on: automation) }
            }
            if rule != nil {
                Button("Edit", systemImage: "pencil", action: onOpen)
            }
        }
        .task(id: automation.state) {
            guard automation.state != "on" else { disabledBy = nil; return }
            let entries = await store.logbook(of: automation.entityID, since: .now.addingTimeInterval(-30 * 86_400))
            disabledBy = entries.last { $0.state == "off" }?.userID.flatMap(store.personName(userID:))
        }
    }

    private var footer: String {
        guard automation.state == "on" else {
            return disabledBy.map { String(localized: "Disabled by \($0)") } ?? String(localized: "Disabled")
        }
        if runsToday.count > 1, let last = runsToday.map(\.start).max(), Calendar.current.component(.hour, from: last) < 6 {
            return String(localized: "Ran \(runsToday.count) times last night")
        }
        if runsToday.count > 1 {
            return String(localized: "Ran \(runsToday.count) times today")
        }
        if let id = rule?.id, let created = ProposedRules.createdAt(id), automation.lastTriggered.map({ $0 < created }) ?? true {
            return Calendar.current.isDateInToday(created)
                ? String(localized: "Created today from a finding")
                : String(localized: "Created \(created.formatted(.relative(presentation: .named))) from a finding")
        }
        guard let last = automation.lastTriggered else { return String(localized: "Never run") }
        if Calendar.current.isDateInToday(last) {
            return String(localized: "Ran today at \(Phrasing.time(last))")
        }
        if Calendar.current.isDateInYesterday(last) {
            return String(localized: "Ran yesterday at \(Phrasing.time(last))")
        }
        return String(localized: "Ran \(last.formatted(.relative(presentation: .named)))")
    }
}

#Preview {
    AutomationsView()
        .environment(DemoHome.store())
}
