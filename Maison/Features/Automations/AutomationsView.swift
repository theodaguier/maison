import SwiftUI

struct AutomationsView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var filter: Filter = .all

    enum Filter: Hashable { case all, enabled, disabled }

    var body: some View {
        NavigationStack {
            Group {
                if store.automations.isEmpty {
                    ContentUnavailableView(
                        "No Automations",
                        systemImage: "clock",
                        description: Text("Automations run on your server, even when your iPhone is off.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            PillPicker(options: [(.all, "All", nil), (.enabled, "Enabled", nil), (.disabled, "Disabled", nil)], selection: $filter)
                            RunsTodayCard(automations: store.automations)
                            HStack(alignment: .firstTextBaseline) {
                                Text("Rules").font(.roundedTitle3)
                                Spacer()
                                Text("Run by your server")
                                    .font(.roundedFootnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 10)
                            ForEach(filtered) { automation in
                                AutomationCard(automation: automation)
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.bottom, 24)
                    }
                    .background(Theme.background)
                    .scrollEdgeEffectStyle(.hard, for: .top)
                }
            }
            .navigationTitle("Automations")
            .toolbar {
                if let serverURL = store.serverURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Automation", systemImage: "plus") {
                            openURL(serverURL.appending(path: "config/automation/edit/new"))
                        }
                    }
                }
            }
        }
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

/// How many rules ran today, with a bar per hour.
private struct RunsTodayCard: View {
    let automations: [EntityState]

    var body: some View {
        let runs = automations.compactMap(\.lastTriggered).filter { Calendar.current.isDateInToday($0) }
        let hours = Set(runs.map { Calendar.current.component(.hour, from: $0) })
        let enabled = automations.filter { $0.state == "on" }.count

        VStack(alignment: .leading, spacing: 0) {
            Label("Rules Run Today", systemImage: "bolt.fill")
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 12)
            Theme.separator.frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    NumberLabel(value: "\(runs.count)", unit: String(localized: "today"), size: .xLarge)
                    Spacer()
                    Text("\(enabled) of \(automations.count) rules enabled")
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        Capsule()
                            .fill(hours.contains(hour) ? Color.indigo : Theme.gaugeTrack)
                            .frame(width: 6, height: hours.contains(hour) ? 22 : 6)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 24)
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

    var body: some View {
        let isOn = automation.state == "on"
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(automation.name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
                    .lineLimit(2)
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { isOn },
                    set: { on in Task { await store.call("automation", on ? "turn_on" : "turn_off", on: automation) } }
                ))
                .labelsHidden()
                .tint(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Theme.separator.frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: footerSymbol)
                    .foregroundStyle(isOn ? Color.green : Color.secondary)
                Text(footer)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.roundedFootnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .cardStyle()
        .contextMenu {
            Button("Run Now", systemImage: "play.fill") {
                Task { await store.call("automation", "trigger", on: automation) }
            }
        }
    }

    private var footerSymbol: String {
        automation.state == "on" ? "checkmark.circle.fill" : "pause.circle"
    }

    private var footer: String {
        guard automation.state == "on" else { return String(localized: "Disabled") }
        guard let last = automation.lastTriggered else { return String(localized: "Never run") }
        if Calendar.current.isDateInToday(last) {
            return String(localized: "Ran today at \(last.formatted(date: .omitted, time: .shortened))")
        }
        if Calendar.current.isDateInYesterday(last) {
            return String(localized: "Ran yesterday at \(last.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Ran \(last.formatted(.relative(presentation: .named)))")
    }
}

#Preview {
    AutomationsView()
        .environment(DemoHome.store())
}
