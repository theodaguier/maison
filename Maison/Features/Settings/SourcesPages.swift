import SwiftUI

// Settings › Sources › Add a Source: every source the home can have, what is there, and the way to
// add the rest. Integrations are the server's own, found on the network or searched; Maison runs their
// steps here, so nobody has to open Home Assistant.

extension SourceSection {
    var title: LocalizedStringKey {
        switch self {
        case .energy: "Energy"
        case .comfort: "Comfort"
        case .network: "Network"
        case .safety: "Safety"
        case .iPhone: "On This iPhone"
        }
    }

    var color: Color {
        switch self {
        case .energy: .orange
        case .comfort: .teal
        case .network: .blue
        case .safety: .red
        case .iPhone: .indigo
        }
    }

    var symbol: String {
        switch self {
        case .energy: "bolt.fill"
        case .comfort: "thermometer.medium"
        case .network: "wifi"
        case .safety: "exclamationmark.shield.fill"
        case .iPhone: "iphone"
        }
    }
}

/// An integration to add: found on the network (with its flow) or picked in the catalog.
struct FlowTarget: Identifiable, Hashable {
    let domain: String
    let name: String
    var flowID: String?
    var id: String { flowID ?? domain }
}

struct AllSourcesPage: View {
    @Environment(HomeStore.self) private var store
    @State private var sources: [DataSource] = []
    @State private var catalog: [IntegrationDescription] = []
    @State private var discovered: [DiscoveredDevice] = []
    @State private var query = ""
    @State private var adding: FlowTarget?
    @State private var opened: DataSource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                Text("Maison already works with nothing more. Each source makes a score more accurate, and Maison sets it up by itself.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                IntegrationSearchField(query: $query)
                if !query.isEmpty {
                    IntegrationResults(query: query, catalog: catalog) { adding = $0 }
                } else {
                    if !sources.isEmpty {
                        CoverageCard(coverage: HomeStore.coverage(of: sources))
                    }
                    if !discovered.isEmpty {
                        DiscoveredGroup(devices: discovered, catalog: catalog) { adding = $0 }
                    }
                    ForEach(SourceSection.allCases, id: \.self) { section in
                        let rows = sources.filter { $0.section == section }
                        if !rows.isEmpty {
                            SettingsGroup(section.title) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, source in
                                    if index > 0 { SettingsDivider() }
                                    NavigationLink { SourceDetailPage(source: source) } label: { SourceRow(source: source) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Text("Nothing to do in Home Assistant. What you enter is a starting point: a sensor replaces it as soon as one appears.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("All Sources")
        .navigationSubtitle(sources.isEmpty ? "" : String(localized: "\(sources.count(where: \.isInPlace)) in place"))
        .sheet(item: $adding, onDismiss: { Task { await load() } }) { IntegrationFlowSheet(target: $0) }
        .navigationDestination(item: $opened) { SourceDetailPage(source: $0) }
        .task {
            await load()
            #if DEBUG
            if let id = UserDefaults.standard.string(forKey: "source") { opened = sources.first { $0.id == id } }
            // `-addIntegration shelly` opens the steps to add it.
            if let domain = UserDefaults.standard.string(forKey: "addIntegration") { adding = FlowTarget(domain: domain, name: domain.capitalized) }
            #endif
        }
        .refreshable { await load() }
    }

    private func load() async {
        sources = await store.dataSources(store.sourceFacts())
        discovered = await store.discoveredDevices()
        if catalog.isEmpty { catalog = await store.integrationCatalog() }
    }
}

/// One source: its symbol, what it brings or where it is, and whether it's there.
struct SourceRow: View {
    let source: DataSource

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: source.symbol, color: source.section.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title).font(.roundedBody).foregroundStyle(.primary).lineLimit(1)
                Text(source.detail).font(.roundedFootnote).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            switch source.state {
            case .inPlace(let value):
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(value).font(.roundedSubheadline).foregroundStyle(.secondary).lineLimit(1)
            case .entered(let value):
                Text(value).font(.roundedSubheadline).foregroundStyle(.secondary).lineLimit(1)
            case .missing:
                Text("Add").font(.roundedSubheadline).foregroundStyle(.blue)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// How far each score rests on measurements, with a segment per possible source.
private struct CoverageCard: View {
    let coverage: [SourceCoverage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What Maison Measures")
                .font(.roundedTitle3)
                .padding(.leading, 4)
                .padding(.top, 10)
            VStack(spacing: 14) {
                ForEach(Array(coverage.enumerated()), id: \.element.section) { index, item in
                    if index > 0 { Theme.separator.frame(height: 1) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: item.section.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(item.section.color, in: .rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.section.title).font(.roundedHeadline)
                                Text("\(item.inPlace) sources of \(item.total)").font(.roundedFootnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            OriginTag(origin: item.isMeasured ? .measured : .estimated)
                        }
                        HStack(spacing: 3) {
                            ForEach(0..<item.total, id: \.self) { segment in
                                Capsule()
                                    .fill(segment < item.inPlace ? item.section.color : Theme.gaugeTrack)
                                    .frame(height: 6)
                            }
                        }
                        .padding(.leading, 40)
                    }
                }
            }
            .padding(16)
            .cardStyle()
        }
    }
}

/// Devices the server found on the network: one tap adds them.
private struct DiscoveredGroup: View {
    let devices: [DiscoveredDevice]
    let catalog: [IntegrationDescription]
    let add: (FlowTarget) -> Void

    var body: some View {
        SettingsGroup("Found on Your Network") {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 { SettingsDivider() }
                let brand = catalog.first { $0.domain == device.domain }?.name ?? device.domain.replacingOccurrences(of: "_", with: " ").capitalized
                Button {
                    add(FlowTarget(domain: device.domain, name: device.name ?? brand, flowID: device.flowID))
                } label: {
                    SettingsRow(title: LocalizedStringKey(device.name ?? brand), detail: device.name == nil ? nil : brand) {
                        IntegrationLogoView(domain: device.domain)
                    }
                    .overlay(alignment: .trailing) { Text("Add").font(.roundedSubheadline).foregroundStyle(.blue) }
                }
                .buttonStyle(.plain)
            }
        }
        Text("Found by your server. Maison adds them without asking anything, except a code when the device shows one.")
            .font(.roundedFootnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct IntegrationSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Brand, device or service", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.roundedBody)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.gaugeTrack, in: .capsule)
    }
}

/// The server's integrations matching the search, by how they're added.
private struct IntegrationResults: View {
    @Environment(HomeStore.self) private var store
    let query: String
    let catalog: [IntegrationDescription]
    let add: (FlowTarget) -> Void

    var body: some View {
        let results = Array(IntegrationDescription.search(query, in: catalog).prefix(40))
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            let groups: [(LocalizedStringKey, [IntegrationDescription])] = [
                ("On the Network", results.filter { !$0.isCloud }),
                ("With an Account", results.filter(\.isCloud)),
            ]
            ForEach(groups.filter { !$0.1.isEmpty }, id: \.1.first?.domain) { title, items in
                SettingsGroup(title) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SettingsDivider() }
                        let installed = store.integrations.contains { $0.domain == item.domain }
                        Button { add(FlowTarget(domain: item.domain, name: item.name)) } label: {
                            SettingsRow(title: LocalizedStringKey(item.name), detail: installed ? String(localized: "Already added") : nil,
                                        showsChevron: true) {
                                IntegrationLogoView(domain: item.domain)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Your server’s integrations, set up by Maison.")
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The brand's logo on a white tile, as an app icon.
struct IntegrationLogoView: View {
    let domain: String
    var size: CGFloat = 30

    var body: some View {
        IntegrationLogo(domain: domain, size: size * 0.76)
            .frame(width: size, height: size)
            .background(.white, in: .rect(cornerRadius: size * 0.27))
            .overlay { RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(Theme.cardBorder, lineWidth: 1) }
    }
}

// MARK: - One source

struct SourceDetailPage: View {
    @Environment(HomeStore.self) private var store
    let source: DataSource
    @State private var editsTariff = false
    @State private var searches = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: source.symbol, color: source.section.color)
                    Text(source.detail).font(.roundedSubheadline).foregroundStyle(.secondary)
                }
                let entities = source.entityIDs.compactMap { store.states[$0] }
                if !entities.isEmpty {
                    SettingsGroup("In Place") {
                        ForEach(Array(entities.enumerated()), id: \.element.entityID) { index, entity in
                            if index > 0 { SettingsDivider() }
                            SettingsRow(title: LocalizedStringKey(entity.name), detail: store.area(of: entity)?.name, value: entity.stateLabel) {
                                SettingsIcon(symbol: entity.symbolName, color: source.section.color)
                            }
                        }
                    }
                }
                setup
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(source.title)
        .sheet(isPresented: $editsTariff) { EnergyTariffEditor(tariff: EnergyTariff.load()) {} }
        .navigationDestination(isPresented: $searches) { IntegrationSearchPage() }
    }

    @ViewBuilder private var setup: some View {
        switch source.setup {
        case .meter:
            if !source.isInPlace {
                let gridOperator = MaisonRelay.url == nil ? nil : GridOperator.supported(in: store.serverConfig?.country)
                if let gridOperator { GridLinkCard(gridOperator: gridOperator) }
                MeterProposal(reading: .forCountry(store.serverConfig?.country), isAlternative: gridOperator != nil)
            }
        case .tariff:
            WideButton(title: source.isInPlace ? "Change Your Tariff" : "Enter Your Tariff", style: .primary) { editsTariff = true }
            Text("The prices on your bill. A bill or a contract read by Maison will replace them.")
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
        case .internetCheck:
            if !source.isInPlace {
                if store.isAdministrator {
                    WideButton(title: "Add It Now", style: .primary) { Task { await store.addInternetCheck() } }
                } else {
                    Text("An administrator of the household can add it from their iPhone.")
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .presence:
            SettingsGroup { PresenceRow() }
        case .device:
            VStack(alignment: .leading, spacing: 12) {
                Label(source.isInPlace ? "Add Another One" : "How to Add One", systemImage: "sparkles")
                    .labelStyle(.compact)
                    .font(.roundedHeadline)
                Text("Plug it in and connect it to your Wi-Fi: Maison finds it on the network and adds it by itself. If it needs an account, look for its brand.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                WideButton(title: "Look for Its Brand", style: .secondary) { searches = true }
            }
            .padding(16)
            .cardStyle()
        }
    }
}

struct IntegrationSearchPage: View {
    @Environment(HomeStore.self) private var store
    @State private var catalog: [IntegrationDescription] = []
    @State private var query = ""
    @State private var adding: FlowTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                IntegrationSearchField(query: $query)
                if query.isEmpty {
                    Text("\(catalog.count) integrations, from your server.")
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                } else {
                    IntegrationResults(query: query, catalog: catalog) { adding = $0 }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Add a Source")
        .sheet(item: $adding) { IntegrationFlowSheet(target: $0) }
        .task { catalog = await store.integrationCatalog() }
    }
}

// MARK: - Adding an integration

/// Runs an integration's steps: a form, a menu, a page to sign in on, until it is added.
struct IntegrationFlowSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let target: FlowTarget

    @State private var driver: (any FlowDriver)?
    @State private var step: FlowStep?
    @State private var wording = FlowWording(domain: "", resources: [:])
    @State private var answers: [String: JSONValue] = [:]
    @State private var isWorking = false
    @State private var error: String?
    @State private var notAllowed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IntegrationLogoView(domain: target.domain, size: 48)
                        Text(target.name).font(.roundedTitle3)
                    }
                    .listRowBackground(Color.clear)
                }
                content
                if let error {
                    Section { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Add a Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { close() }
                }
                if case .form(let form) = step, !form.hasUnsupportedRequirement {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { Task { await submit(form) } }
                            .disabled(isWorking || !isComplete(form))
                    }
                }
            }
        }
        .task { await begin() }
    }

    @ViewBuilder private var content: some View {
        if notAllowed {
            Section { Text("Adding a source needs an administrator of the household.").foregroundStyle(.secondary) }
        } else {
            switch step {
            case nil:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .form(let form):
                formContent(form)
            case .menu(let flowID, let stepID, let options):
                Section {
                    ForEach(options, id: \.self) { option in
                        Button(wording.menuOption(option, step: stepID)) {
                            Task { await run { try await $0.submit(flowID, answers: ["next_step_id": .string(option)]) } }
                        }
                    }
                }
            case .external(let flowID, _, let url):
                Section {
                    Text("\(target.name) asks you to sign in on its own site. Your password stays there: Maison never sees it.")
                        .foregroundStyle(.secondary)
                    Button("Sign In") { openURL(url) }
                    Button("I’ve Signed In") { Task { await resume(flowID) } }
                }
            case .progress(let flowID, _):
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Your server is setting it up…").foregroundStyle(.secondary)
                    }
                }
                .task(id: flowID) { await poll(flowID) }
            case .created:
                Section {
                    Label("Added. Its devices appear in a few seconds.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Done") { dismiss() }
                }
            case .aborted(let reason):
                Section {
                    Text(abortText(reason)).foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func formContent(_ form: FlowStep.Form) -> some View {
        Section {
            ForEach(form.fields) { field in
                FlowFieldRow(field: field, label: wording.label(field: field.name, step: form.stepID),
                             help: wording.help(field: field.name, step: form.stepID), answers: $answers,
                             error: form.errors[field.name].map { wording.error($0) ?? $0 })
            }
            if form.fields.isEmpty {
                Button("Add") { Task { await submit(form) } }.disabled(isWorking)
            }
        } header: {
            if let title = wording.title(step: form.stepID) { Text(title) }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let description = wording.description(step: form.stepID, placeholders: form.placeholders) {
                    Text(LocalizedStringKey(description))
                }
                if let base = form.errors["base"] { Text(wording.error(base) ?? base).foregroundStyle(.orange) }
                if form.hasUnsupportedRequirement {
                    Text("This step asks for a setting Maison can’t show yet.").foregroundStyle(.orange)
                }
            }
        }
    }

    private func abortText(_ reason: String) -> String {
        if reason == "already_configured" || reason == "single_instance_allowed" { return String(localized: "It’s already added.") }
        return wording.abort(reason) ?? String(localized: "Your server couldn’t add it (\(reason)).")
    }

    private func isComplete(_ form: FlowStep.Form) -> Bool {
        form.fields.allSatisfy { field in
            guard field.isRequired, field.defaultValue == nil else { return true }
            switch field.kind {
            case .toggle, .constant, .unsupported: return true
            default: return answers[field.name].map { $0 != .string("") } ?? false
            }
        }
    }

    private func begin() async {
        guard let driver = await store.flowDriver() else { notAllowed = true; return }
        self.driver = driver
        wording = await store.flowWording(domain: target.domain)
        await run { driver in
            if let flowID = target.flowID { try await driver.current(flowID) } else { try await driver.start(target.domain) }
        }
    }

    private func submit(_ form: FlowStep.Form) async {
        var values: [String: JSONValue] = [:]
        for field in form.fields {
            if case .constant(let value) = field.kind { values[field.name] = value; continue }
            if case .unsupported = field.kind { continue }
            if let value = answers[field.name] ?? field.defaultValue { values[field.name] = value }
        }
        await run { try await $0.submit(form.flowID, answers: values) }
    }

    /// After signing in on the brand's site: the server moves on by itself, or with an empty answer.
    private func resume(_ flowID: String) async {
        await run { driver in
            let current = try await driver.current(flowID)
            if case .progress = current { return try await driver.submit(flowID, answers: [:]) }
            return current
        }
    }

    private func poll(_ flowID: String) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard let driver, let next = try? await driver.current(flowID) else { continue }
            if case .progress = next { continue }
            await apply(next)
            return
        }
    }

    private func run(_ action: (any FlowDriver) async throws -> FlowStep) async {
        guard let driver else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            await apply(try await action(driver))
        } catch {
            self.error = String(localized: "Your server didn’t answer. Try again in a moment.")
        }
    }

    private func apply(_ next: FlowStep) async {
        if case .form(let form) = next {
            // Defaults show in the fields, and stay the answer unless changed.
            for field in form.fields where answers[field.name] == nil { answers[field.name] = field.defaultValue }
        }
        step = next
        if case .created = next { await store.integrationAdded(target.domain) }
    }

    private func close() {
        // A flow Maison started is dropped; one the server started for a found device stays for later.
        if target.flowID == nil, let flowID = step?.flowID, let driver { Task { await driver.cancel(flowID) } }
        dismiss()
    }
}

/// One field of a flow's form.
private struct FlowFieldRow: View {
    let field: FlowField
    let label: String
    let help: String?
    @Binding var answers: [String: JSONValue]
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            input
            if let help { Text(LocalizedStringKey(help)).font(.roundedFootnote).foregroundStyle(.secondary) }
            if let error { Text(error).font(.roundedFootnote).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder private var input: some View {
        switch field.kind {
        case .text(let isSecret):
            let text = Binding(get: { answers[field.name]?.stringValue ?? "" }, set: { answers[field.name] = .string($0) })
            if isSecret {
                SecureField(label, text: text)
            } else {
                TextField(label, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .number(let isInteger):
            TextField(label, value: Binding(get: { answers[field.name]?.doubleValue }, set: { answers[field.name] = $0.map(JSONValue.number) }),
                      format: .number.precision(.fractionLength(0...(isInteger ? 0 : 3))))
                .keyboardType(isInteger ? .numberPad : .decimalPad)
        case .toggle:
            Toggle(label, isOn: Binding(get: { answers[field.name]?.boolValue ?? false }, set: { answers[field.name] = .bool($0) }))
        case .choice(let choices):
            Picker(label, selection: Binding(get: { answers[field.name]?.stringValue ?? "" }, set: { answers[field.name] = .string($0) })) {
                if !field.isRequired || answers[field.name] == nil { Text("Choose…").tag("") }
                ForEach(choices, id: \.self) { Text($0.label).tag($0.value) }
            }
        case .constant(let value):
            LabeledContent(label, value: value.stringValue ?? "")
        case .unsupported:
            LabeledContent(label, value: String(localized: "Not available here"))
                .foregroundStyle(.secondary)
        }
    }
}
