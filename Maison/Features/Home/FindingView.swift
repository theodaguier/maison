import SwiftUI

/// One finding: what Maison noticed, what it's worth, why, and the tap that fixes it.
struct FindingView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let finding: Finding
    /// Called with the rule once it is saved, so Home can confirm it and offer to undo.
    var ruleCreated: (AutomationRule) -> Void = { _ in }
    @State private var isSaving = false
    @State private var error: String?
    @State private var asksWhatsWrong = false
    @State private var editsTariff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(finding.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        NumberLabel(value: finding.yearlyValue.formatted(.number.precision(.fractionLength(0))),
                                    unit: String(localized: "\(finding.currency.currencySymbol) a year"), size: .xLarge)
                        Text("to save every year").font(.roundedFootnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Estimated").font(.roundedHeadline).foregroundStyle(.orange)
                        Text("from your tariff").font(.roundedSubheadlineEmphasized).foregroundStyle(.secondary)
                    }
                    .padding(.top, 18)
                }
                DayTimeline(usage: finding.usage, offPeak: finding.offPeak)
                Text("Why").font(.roundedTitle3)
                VStack(spacing: 0) {
                    ForEach(Array(finding.reasons.enumerated()), id: \.offset) { index, reason in
                        if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 60) }
                        HStack(spacing: 14) {
                            Image(systemName: reason.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(color(reason.origin), in: .rect(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reason.title).font(.roundedHeadline)
                                Text(reason.detail).font(.roundedFootnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            OriginTag(origin: reason.origin)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .cardStyle()
                if let rule = finding.rule {
                    Button {
                        Task { await create(rule) }
                    } label: {
                        Group {
                            if isSaving { ProgressView() } else { Text("Run It in Off-Peak Hours") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isSaving)
                }
                if let error {
                    Text(error).font(.roundedFootnote).foregroundStyle(.orange)
                }
                HStack(spacing: 28) {
                    Button("Ignore") {
                        FindingFeedback.ignore(finding.id)
                        dismiss()
                    }
                    Button("This Isn’t Right") { asksWhatsWrong = true }
                }
                .font(.roundedSubheadlineEmphasized)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(finding.deviceName)
        .navigationBarTitleDisplayMode(.inline)
        .errorFeedback(error)
        .confirmationDialog("What’s Wrong?", isPresented: $asksWhatsWrong, titleVisibility: .visible) {
            Button(String(localized: "It doesn’t run at \(busiestHour):00")) { wrong() }
            Button("My Off-Peak Hours Are Different") { editsTariff = true }
            Button("It’s Already Set to Off-Peak Hours") { wrong() }
            Button("Something Else") { wrong() }
        } message: {
            Text("Maison takes it into account for its next findings.")
        }
        .sheet(isPresented: $editsTariff) { EnergyTariffEditor(tariff: EnergyTariff.load()) { dismiss() } }
    }

    private var busiestHour: Int { finding.usage.max { $0.value < $1.value }?.key ?? 0 }

    private func color(_ origin: ValueOrigin) -> Color {
        switch origin {
        case .measured: .green
        case .estimated: .orange
        case .entered: .blue
        }
    }

    private func wrong() {
        FindingFeedback.ignore(finding.id)
        dismiss()
    }

    private func create(_ rule: AutomationRule) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(rule)
            ProposedRules.add(rule.id)
            FindingFeedback.ignore(finding.id)
            ruleCreated(rule)
            dismiss()
        } catch {
            self.error = String(localized: "Couldn’t create the rule. Editing automations needs an administrator account.")
        }
    }
}

/// Yesterday, 6 am to 6 am: when the device ran, and the off-peak hours.
private struct DayTimeline: View {
    let usage: [Int: Double]
    let offPeak: EnergyTariff.OffPeak?

    /// Hours from 6 am, so the night is in one piece.
    private let hours = Array(6..<24) + Array(0..<6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yesterday").font(.roundedSubheadlineEmphasized).foregroundStyle(.secondary)
            GeometryReader { proxy in
                let width = proxy.size.width / 24
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.gaugeTrack).frame(height: 14)
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        if offPeak?.contains(hour: hour) == true {
                            Rectangle().fill(Color.green).frame(width: width, height: 14).offset(x: Double(index) * width)
                        }
                    }
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        if (usage[hour] ?? 0) > 0.05 {
                            Rectangle().fill(Color.orange).frame(width: width, height: 14).offset(x: Double(index) * width)
                        }
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 14)
            HStack {
                Text(hourText(Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: .now) ?? .now))
                Spacer()
                Text(hourText(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now))
                Spacer()
                Text(hourText(Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: .now) ?? .now))
            }
            .font(.roundedFootnote)
            .foregroundStyle(.tertiary)
            HStack(spacing: 16) {
                Label("It runs", systemImage: "circle.fill").foregroundStyle(.orange)
                if offPeak != nil {
                    Label("Off-peak hours", systemImage: "circle.fill").foregroundStyle(.green)
                }
            }
            .labelStyle(.compact)
            .font(.roundedFootnote)
        }
        .padding(16)
        .cardStyle()
    }
}

/// The tariff, entered: one price, or peak and off-peak prices with their hours.
struct EnergyTariffEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var price: Double?
    @State private var hasOffPeak: Bool
    @State private var offPeakPrice: Double?
    @State private var startHour: Int
    @State private var endHour: Int
    let saved: () -> Void

    init(tariff: EnergyTariff?, saved: @escaping () -> Void) {
        _price = State(initialValue: tariff?.price)
        _hasOffPeak = State(initialValue: tariff?.offPeak != nil)
        _offPeakPrice = State(initialValue: tariff?.offPeak?.price)
        _startHour = State(initialValue: tariff?.offPeak?.startHour ?? 22)
        _endHour = State(initialValue: tariff?.offPeak?.endHour ?? 6)
        self.saved = saved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tariff", selection: $hasOffPeak) {
                        Text("Base").tag(false)
                        Text("Off-Peak Hours").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField(hasOffPeak ? "Peak price per kWh" : "Price per kWh", value: $price, format: .number.precision(.fractionLength(0...4)))
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("The prices on your bill, taxes included.")
                }
                if hasOffPeak {
                    Section("Off-Peak Hours") {
                        TextField("Off-peak price per kWh", value: $offPeakPrice, format: .number.precision(.fractionLength(0...4)))
                            .keyboardType(.decimalPad)
                        Picker("From", selection: $startHour) {
                            ForEach(0..<24, id: \.self) { Text(verbatim: hourText(at: $0)).tag($0) }
                        }
                        Picker("To", selection: $endHour) {
                            ForEach(0..<24, id: \.self) { Text(verbatim: hourText(at: $0)).tag($0) }
                        }
                    }
                }
            }
            .navigationTitle("Your Tariff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        guard let price else { return }
                        let offPeak = hasOffPeak ? offPeakPrice.map { EnergyTariff.OffPeak(price: $0, startHour: startHour, endHour: endHour) } : nil
                        EnergyTariff(price: price, offPeak: offPeak).save()
                        saved()
                        dismiss()
                    }
                    .disabled((price ?? 0) <= 0 || (hasOffPeak && (offPeakPrice ?? 0) <= 0) || startHour == endHour)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func hourText(at hour: Int) -> String {
        Maison.hourText(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now)
    }
}

/// "Rule created: water heater in off-peak hours", with See and Undo, at the bottom of Home.
struct RuleCreatedBanner: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.selectTab) private var selectTab
    let rule: AutomationRule
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Rule created: \(rule.name)")
                .lineLimit(1)
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Button("See") {
                selectTab(.rules)
                close()
            }
            Button("Undo") {
                ProposedRules.remove(rule.id)
                Task { try? await store.delete(rule) }
                close()
            }
        }
        .font(.roundedSubheadlineEmphasized)
        .tint(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.12), in: .capsule)
        .padding(.horizontal, Theme.screenPadding)
        .task {
            try? await Task.sleep(for: .seconds(8))
            close()
        }
    }
}
