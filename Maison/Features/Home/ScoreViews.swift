import AuthenticationServices
import Charts
import SwiftUI
import UserNotifications

/// The three V1 scores, in the order of the home screen.
enum ScoreKind: String, CaseIterable, Identifiable {
    case comfort, energy, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfort: String(localized: "Comfort")
        case .energy: String(localized: "Energy")
        case .network: String(localized: "Network")
        }
    }

    var color: Color {
        switch self {
        case .comfort: .orange
        case .energy: .yellow
        case .network: .cyan
        }
    }

    var symbol: String {
        switch self {
        case .comfort: "thermometer.medium"
        case .energy: "bolt.fill"
        case .network: "wifi"
        }
    }

    var analytics: AnalyticsScore {
        switch self {
        case .comfort: .comfort
        case .energy: .energy
        case .network: .network
        }
    }

    func percent(in scores: HomeScores?) -> Int? {
        switch self {
        case .comfort: scores?.comfort?.percent
        case .energy: scores?.energy?.percent
        case .network: scores?.network?.percent
        }
    }

    /// What the ring shows before its percentage exists: the electricity used so far, until three days
    /// give a habit to compare with.
    func reading(in scores: HomeScores?) -> (value: String, unit: String)? {
        guard self == .energy, let energy = scores?.energy, energy.percent == nil else { return nil }
        return (energy.today.formatted(.number.precision(.fractionLength(0...1))), energy.unit)
    }
}

// MARK: - Home

/// The three rings side by side. Each opens its fiche.
struct ScoresCard: View {
    let scores: HomeScores?
    var isDimmed = false
    let open: (ScoreKind) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ScoreKind.allCases.enumerated()), id: \.element) { index, kind in
                if index > 0 {
                    Theme.separator.frame(width: 1, height: 110)
                }
                Button { open(kind) } label: {
                    ScoreRing(kind: kind, percent: kind.percent(in: scores), reading: kind.reading(in: scores), isLoading: scores == nil)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .opacity(isDimmed ? 0.5 : 1)
        .cardStyle()
    }
}

private struct ScoreRing: View {
    let kind: ScoreKind
    let percent: Int?
    /// Shown in the ring while there is no percentage yet.
    var reading: (value: String, unit: String)?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 8) {
            // An empty ring has no arc at all, not the dot a zero progress leaves.
            ProgressRing(progress: Double(percent ?? 0) / 100, color: percent == nil ? Color.clear : kind.color, lineWidth: 12) {
                if let percent {
                    NumberLabel(value: "\(percent)", unit: "%", size: .small, unitStyle: AnyShapeStyle(.primary))
                        .contentTransition(.numericText(value: Double(percent)))
                } else if let reading {
                    NumberLabel(value: reading.value, unit: reading.unit, size: .small, unitStyle: AnyShapeStyle(.secondary))
                } else if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(verbatim: "–")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 92, height: 92)
            Text(kind.title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .animation(.smooth, value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(percent.map { "\($0) %" } ?? reading.map { "\($0.value) \($0.unit)" } ?? String(localized: "Not measured yet"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The one thing to look at today. Safety would come first; for now, the weakest score's reason.
struct Attention: Equatable {
    let kind: ScoreKind
    let title: String
    let detail: String
    /// Set when the card opens a finding rather than the score's fiche.
    var findingID: String?

    static func pick(from scores: HomeScores?, meterProposalSeen: Bool = MeterProposalSetting.wasSeen) -> Attention? {
        guard let scores else { return nil }
        if let outage = scores.network?.outages.max(by: { $0.duration < $1.duration }) {
            return Attention(
                kind: .network,
                title: String(localized: "The internet dropped at \(outage.start.formatted(date: .omitted, time: .shortened))"),
                detail: String(localized: "Cut for \(Self.minutes(outage.duration))")
            )
        }
        if let finding = scores.findings.first {
            return Attention(
                kind: .energy,
                title: finding.title,
                detail: String(localized: "About \(finding.yearlyValue.formatted(.number.precision(.fractionLength(0)))) \(finding.currency.currencySymbol) more a year"),
                findingID: finding.id
            )
        }
        if let room = scores.comfort?.rooms.first(where: { $0.excursion != nil }), let excursion = room.excursion {
            let hour = hourText(excursion.interval.start)
            return Attention(
                kind: .comfort,
                title: excursion.side == .tooWarm
                    ? String(localized: "\(room.name) was too warm around \(hour)")
                    : String(localized: "\(room.name) was too cold around \(hour)"),
                detail: String(localized: "\(room.percent) % of the day in your range")
            )
        }
        if !scores.hasElectricityMeter, !meterProposalSeen {
            return Attention(
                kind: .energy,
                title: String(localized: "Your meter can talk to Maison"),
                detail: String(localized: "A small reader, then nothing to set up")
            )
        }
        if let energy = scores.energy, let difference = energy.difference, difference > 0.1 {
            return Attention(
                kind: .energy,
                title: Calendar.current.isDateInToday(energy.day)
                    ? String(localized: "More electricity than usual today")
                    : String(localized: "More electricity than usual yesterday"),
                detail: String(localized: "\(Int((difference * 100).rounded())) % over your habit")
            )
        }
        return nil
    }

    static func minutes(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}

struct AttentionCard: View {
    let attention: Attention
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: attention.kind.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(attention.kind.color, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("To Look At Today, \(attention.kind.title)")
                        .font(.roundedFootnoteEmphasized)
                        .foregroundStyle(.secondary)
                    Text(attention.title)
                        .font(.roundedHeadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(attention.detail)
                        .font(.roundedSubheadline)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.pressable)
    }
}

extension HomeScores {
    /// One sentence per score that has something to say, for the summary card.
    var sentences: [String] {
        var result: [String] = []
        if let comfort {
            let outside = comfort.rooms.filter { $0.excursion != nil }
            if outside.isEmpty {
                result.append(String(localized: "\(comfort.percent) % comfort: every room stayed in your range."))
            } else {
                let names = outside.map(\.name).formatted(.list(type: .and))
                result.append(String(localized: "\(comfort.percent) % comfort: every room stayed in your range, except \(names)."))
            }
        }
        if let energy, let difference = energy.difference {
            let percent = Int((abs(difference) * 100).rounded())
            if Calendar.current.isDateInToday(energy.day) {
                result.append(difference < 0
                    ? String(localized: "Energy: \(percent) % under your habit so far.")
                    : String(localized: "Energy: \(percent) % over your habit so far."))
            } else {
                result.append(difference < 0
                    ? String(localized: "Energy yesterday: \(percent) % under your habit.")
                    : String(localized: "Energy yesterday: \(percent) % over your habit."))
            }
        }
        if let network {
            result.append(network.outages.isEmpty
                ? String(localized: "Network at \(network.percent) %, no outage today.")
                : String(localized: "Network at \(network.percent) %: \(network.outages.count) outage today."))
        }
        return result
    }
}

// MARK: - Fiches

/// Opens on top of the home screen when a ring or the card to look at is touched.
struct ScoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ScoreKind
    let scores: HomeScores?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch kind {
                    case .comfort: ComfortFiche(score: scores?.comfort)
                    case .energy: EnergyFiche(score: scores?.energy)
                    case .network: NetworkFiche(score: scores?.network, hasSource: scores?.hasNetworkSource ?? false)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { Analytics.shared.track(.scoreOpened(kind.analytics)) }
    }
}

/// "Measured", "Estimated", "Entered": where a value comes from.
struct OriginTag: View {
    let origin: ValueOrigin

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: .capsule)
    }

    private var title: String {
        switch origin {
        case .measured: String(localized: "Measured")
        case .estimated: String(localized: "Estimated")
        case .entered: String(localized: "Entered")
        }
    }

    private var color: Color {
        switch origin {
        case .measured: .green
        case .estimated: .orange
        case .entered: .blue
        }
    }
}

/// The top of a fiche: the score, where it comes from, and what it means.
private struct FicheHeader: View {
    let value: String
    let unit: String
    let origin: ValueOrigin
    let caption: String
    let status: String
    let statusColor: Color
    let detail: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                NumberLabel(value: value, unit: unit, size: .xLarge)
                HStack(spacing: 6) {
                    OriginTag(origin: origin)
                    Text(caption)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(status)
                    .font(.roundedHeadline)
                    .foregroundStyle(statusColor)
                Text(detail)
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, 22)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a fiche shows while its score can't be computed, with the way forward.
private struct MissingScore: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title).font(.roundedTitle3)
            Text(message)
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Bien, Correct, À surveiller.
private func health(_ percent: Int) -> (String, Color) {
    switch percent {
    case 90...: (String(localized: "Good"), .green)
    case 75...: (String(localized: "Fair"), .orange)
    default: (String(localized: "Needs a Look"), .red)
    }
}

/// "19 h" in French, "19:00" in English.
func hourText(_ date: Date) -> String {
    String(localized: "\(Calendar.current.component(.hour, from: date)):00", comment: "An hour of the day; French writes it 19 h")
}

private func degrees(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}

// MARK: Comfort

private struct ComfortFiche: View {
    @Environment(HomeStore.self) private var store
    let score: ComfortScore?
    @State private var tab: Tab = .rooms
    @State private var editsRange = false

    enum Tab: Hashable { case rooms, temperature, humidity, air }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            scoreSection
            ComfortExtras(score: score)
        }
    }

    @ViewBuilder
    private var scoreSection: some View {
        if let score {
            VStack(alignment: .leading, spacing: 18) {
                let (status, color) = health(score.percent)
                FicheHeader(
                    value: "\(score.percent)",
                    unit: "%",
                    origin: .measured,
                    caption: String(localized: "last 24 hours"),
                    status: status,
                    statusColor: color,
                    detail: "\(degrees(score.range.lowerBound)) – \(degrees(score.range.upperBound))°"
                )
                PillPicker(options: tabs, selection: $tab)
                switch tab {
                case .rooms:
                    VStack(spacing: 20) {
                        ForEach(score.rooms) { RoomComfortRow(room: $0) }
                    }
                case .temperature:
                    RoomValues(deviceClass: "temperature", unit: "°", range: score.range)
                case .humidity:
                    RoomValues(deviceClass: "humidity", unit: " %", range: 40...60)
                case .air:
                    RoomValues(deviceClass: "carbon_dioxide", unit: " ppm", range: 0...1000)
                }
                RangeRow(range: score.range, origin: score.rangeOrigin, isStarting: score.rangeIsStarting) { editsRange = true }
            }
            .sheet(isPresented: $editsRange) { ComfortRangeEditor(range: score.range) }
        } else if store.comfortSensors.isEmpty {
            MissingScore(
                symbol: "thermometer.medium.slash",
                title: "No Temperature in Your Rooms",
                message: "Comfort counts the time each room spends in your range. No temperature reading reaches your server yet, so Maison has nothing to count."
            )
        } else {
            VStack(spacing: 14) {
                MissingScore(
                    symbol: "calendar.badge.clock",
                    title: "Waiting for a Reading",
                    message: "Your thermometers haven’t sent a temperature in the last 24 hours. The score appears with the next one. You can set your range now."
                )
                Button("Set My Range") { editsRange = true }
                    .buttonStyle(.glassProminent)
            }
            .sheet(isPresented: $editsRange) { ComfortRangeEditor(range: 19...22) }
        }
    }

    /// Air appears only when a room measures CO₂.
    private var tabs: [(value: Tab, title: LocalizedStringKey, symbol: String?)] {
        var tabs: [(value: Tab, title: LocalizedStringKey, symbol: String?)] = [(.rooms, "Rooms", nil), (.temperature, "Temperature", nil), (.humidity, "Humidity", nil)]
        if !store.roomCarbonDioxide.isEmpty { tabs.append((.air, "Air", nil)) }
        return tabs
    }
}

private struct RoomComfortRow: View {
    let room: ComfortScore.Room

    var body: some View {
        let color: Color = room.excursion == nil ? .green : .orange
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: Area(id: room.id, name: room.name).symbol)
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(room.name).font(.roundedHeadline)
                Spacer()
                Text(caption)
                    .font(.roundedFootnote)
                    .foregroundStyle(room.excursion == nil ? Color.secondary : Color.orange)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.gaugeTrack)
                    Capsule().fill(color).frame(width: proxy.size.width * Double(room.percent) / 100)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        guard let excursion = room.excursion else { return "\(room.percent) %" }
        let hour = hourText(excursion.interval.start)
        return excursion.side == .tooWarm
            ? String(localized: "\(room.percent) %, too warm around \(hour)")
            : String(localized: "\(room.percent) %, too cold around \(hour)")
    }
}

/// Each room's current reading of one kind, against the household's range.
private struct RoomValues: View {
    @Environment(HomeStore.self) private var store
    let deviceClass: String
    let unit: String
    let range: ClosedRange<Double>

    var body: some View {
        let rows = store.rooms.compactMap { room in store.averageValue(of: deviceClass, in: room).map { (room, $0) } }
        if rows.isEmpty {
            Text("No room measures this yet.")
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.0.id) { index, row in
                    if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 46) }
                    HStack(spacing: 12) {
                        Image(systemName: row.0.symbol)
                            .foregroundStyle(range.contains(row.1) ? Color.green : Color.orange)
                            .frame(width: 22)
                        Text(row.0.name).font(.roundedHeadline)
                        Spacer()
                        Text(degrees(row.1) + unit)
                            .font(.roundedHeadline)
                            .foregroundStyle(range.contains(row.1) ? Color.primary : Color.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .cardStyle()
        }
    }
}

private struct RangeRow: View {
    let range: ClosedRange<Double>
    let origin: ValueOrigin
    var isStarting = false
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 12) {
                Image(systemName: "thermometer.variable")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.orange, in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Range").font(.roundedHeadline)
                    Text(origin == .entered ? String(localized: "Set by you")
                        : isStarting ? String(localized: "A usual range, until Maison learns yours")
                        : String(localized: "Learned from your past week"))
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(degrees(range.lowerBound)) – \(degrees(range.upperBound))°")
                    .font(.roundedHeadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .cardStyle()
        }
        .buttonStyle(.pressable)
    }
}

private struct ComfortRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lower: Double
    @State private var upper: Double

    init(range: ClosedRange<Double>) {
        _lower = State(initialValue: range.lowerBound)
        _upper = State(initialValue: range.upperBound)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $lower, in: 10...(upper - 0.5), step: 0.5) {
                        LabeledContent("From", value: degrees(lower) + "°")
                    }
                    Stepper(value: $upper, in: (lower + 0.5)...32, step: 0.5) {
                        LabeledContent("To", value: degrees(upper) + "°")
                    }
                } footer: {
                    Text("Comfort counts the time each room spends between these two temperatures. The new range counts from the next refresh.")
                }
            }
            .navigationTitle("Your Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        ComfortRangeSetting.set(lower...upper)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: Energy

private struct EnergyFiche: View {
    @Environment(HomeStore.self) private var store
    let score: EnergyScore?
    @State private var tab: Tab = .electricity
    @State private var extras = EnergyExtrasData()
    @State private var editsPrice = false

    enum Tab: Hashable { case electricity, water, cost, devices }

    var body: some View {
        if let score {
            VStack(alignment: .leading, spacing: 18) {
                FicheHeader(
                    value: score.today.formatted(.number.precision(.fractionLength(0...1))),
                    unit: score.unit,
                    origin: .measured,
                    caption: Calendar.current.isDateInToday(score.day) ? String(localized: "since midnight") : String(localized: "yesterday, whole day"),
                    status: status.0,
                    statusColor: status.1,
                    detail: detail
                )
                if tabs.count > 1 {
                    PillPicker(options: tabs, selection: $tab)
                }
                switch tab {
                case .electricity:
                    if !score.lastDay.isEmpty {
                        EnergyChart(hours: score.lastDay, unit: score.unit)
                    }
                case .water:
                    if let water = extras.water {
                        StatTile(symbol: "drop.fill", title: Calendar.current.isDateInToday(score.day) ? String(localized: "Water today") : String(localized: "Water yesterday"),
                                 value: water.value.formatted(.number.precision(.fractionLength(0...1))), unit: water.unit)
                    }
                case .cost:
                    if let price = extras.price, !score.lastDay.isEmpty {
                        EnergyChart(hours: score.lastDay.map { (start: $0.start, value: $0.value * price.perKilowattHour) }, unit: price.currency)
                    }
                case .devices:
                    DeviceEnergyList(devices: extras.devices, unit: score.unit)
                }
                if let top = extras.devices.first {
                    TopDeviceCard(device: top, unit: score.unit, isToday: Calendar.current.isDateInToday(score.day))
                }
                CostTiles(cost: extras.cost, price: extras.price, isToday: Calendar.current.isDateInToday(score.day)) { editsPrice = true }
                if score.usual == nil {
                    MissingScore(
                        symbol: "calendar.badge.clock",
                        title: "Learning Your Habit",
                        message: "The score compares today with the same hours of your previous days. It appears after three days of readings."
                    )
                }
            }
            .task(id: score.asOf) { extras = await EnergyExtrasData.load(store: store, score: score) }
            .sheet(isPresented: $editsPrice) {
                EnergyTariffEditor(tariff: EnergyTariff.load()) {
                    Task { extras = await EnergyExtrasData.load(store: store, score: score) }
                }
            }
        } else if let link = GridLink.load() {
            MissingScore(
                symbol: "bolt.badge.clock",
                title: "Linked to Your Grid Operator",
                message: LocalizedStringKey("\(GridOperator.byCountry.values.first { $0.id == link.operatorID }?.name ?? "") sends the previous day’s readings each morning. The score appears with the first of them.")
            )
        } else {
            VStack(alignment: .leading, spacing: 18) {
                let gridOperator = MaisonRelay.url == nil ? nil : GridOperator.supported(in: store.serverConfig?.country)
                if let gridOperator {
                    GridLinkCard(gridOperator: gridOperator)
                }
                MeterProposal(reading: .forCountry(store.serverConfig?.country), isAlternative: gridOperator != nil)
            }
            .onAppear { MeterProposalSetting.markSeen() }
        }
    }

    /// Only the tabs that have something to show.
    private var tabs: [(value: Tab, title: LocalizedStringKey, symbol: String?)] {
        var tabs: [(value: Tab, title: LocalizedStringKey, symbol: String?)] = [(.electricity, "Electricity", nil)]
        if extras.water != nil { tabs.append((.water, "Water", nil)) }
        if extras.price != nil { tabs.append((.cost, "Cost", nil)) }
        if !extras.devices.isEmpty { tabs.append((.devices, "By Device", nil)) }
        return tabs
    }

    private var status: (String, Color) {
        guard let percent = score?.percent else { return (String(localized: "Measuring"), .secondary) }
        switch percent {
        case 75...: return (String(localized: "Frugal"), .green)
        case 50...: return (String(localized: "Usual"), .secondary)
        default: return (String(localized: "High"), .orange)
        }
    }

    private var detail: String {
        guard let difference = score?.difference else { return String(localized: "No habit yet") }
        let percent = Int((abs(difference) * 100).rounded())
        return difference < 0 ? String(localized: "\(percent) % under your habit") : String(localized: "\(percent) % over your habit")
    }
}

/// Whether the home screen already proposed reading the meter: it does so once, then only in the fiche.
enum MeterProposalSetting {
    static let seenKey = "meterProposalSeen"
    static var wasSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }
}

/// The way without hardware: the grid operator already has the meter's readings, and hands them over
/// once the person approves Maison on its site. They arrive the day after.
struct GridLinkCard: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    let gridOperator: GridOperator
    @State private var isLinking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.yellow, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Without Hardware").font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                    Text("Your readings from \(gridOperator.name)").font(.roundedHeadline)
                }
            }
            Text("Your meter already sends its readings to \(gridOperator.name). Approve Maison once on its site: Maison then receives the previous day’s consumption every morning.")
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await link() }
            } label: {
                Group {
                    if isLinking { ProgressView() } else { Text("Link My \(gridOperator.name) Account") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isLinking)
            if let error {
                Text(error).font(.roundedFootnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .cardStyle()
        .errorFeedback(error)
    }

    private func link() async {
        guard let relay = MaisonRelay.url else { return }
        isLinking = true
        defer { isLinking = false }
        let state = UUID().uuidString
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: EnedisDataConnect(relay: relay).authorizationURL(state: state),
                callbackURLScheme: EnedisDataConnect.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            guard let approved = EnedisDataConnect.link(fromCallback: callback, expectedState: state) else {
                error = String(localized: "\(gridOperator.name) didn’t confirm the link. Try again.")
                return
            }
            GridLink(operatorID: gridOperator.id, meterID: approved.meterID, accessKey: approved.accessKey, linkedAt: .now).save()
            error = nil
            await store.syncGridConsumption()
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            return
        } catch {
            self.error = String(localized: "\(gridOperator.name) couldn’t be reached. Try again in a moment.")
        }
    }
}

/// No meter reaches the server: what reading it brings, and the way that fits the home's country.
/// Once the reader is on the Wi-Fi, Home Assistant finds it and Maison adds it; nothing to set up.
struct MeterProposal: View {
    let reading: MeterReading
    /// Shown under the grid operator's card: the reader is then the way to measure live.
    var isAlternative = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.yellow, in: .rect(cornerRadius: 11))
                Text(title).font(.roundedTitle3)
                Text("Measured, your electricity shows hour by hour, and Maison tells you when it drifts from your habit.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                step(symbol: "cable.connector", color: .yellow, title: what, detail: whatDetail)
                Theme.separator.frame(height: 1).padding(.leading, 60)
                step(symbol: "wifi", color: .cyan, title: String(localized: "Connect it to your Wi-Fi"), detail: String(localized: "With the reader’s own app, once."))
                Theme.separator.frame(height: 1).padding(.leading, 60)
                step(symbol: "sparkles", color: .indigo, title: String(localized: "Maison does the rest"), detail: String(localized: "It finds the reader on your network and adds it by itself."))
            }
            .cardStyle()
            if case .port = reading {
                Text("No access to the meter? A Wi-Fi measuring clamp in your electrical panel works with any meter.")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        if isAlternative { return String(localized: "To Measure It Live") }
        return switch reading {
        case .port: String(localized: "Your Meter Can Talk to Maison")
        case .clamp: String(localized: "Measure Your Electricity")
        }
    }

    private var what: String {
        switch reading {
        case .port(let port): String(localized: "A Wi-Fi reader for the \(port.name) port")
        case .clamp: String(localized: "A Wi-Fi measuring clamp")
        }
    }

    private var whatDetail: String {
        switch reading {
        case .port(.tic): String(localized: "It plugs onto your Linky’s customer terminals, under its cover.")
        case .port: String(localized: "It plugs into your smart meter’s customer port.")
        case .clamp: String(localized: "It goes around the main cable in your electrical panel, and works with any meter.")
        }
    }

    private func step(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.roundedHeadline)
                Text(detail)
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct EnergyChart: View {
    let hours: [(start: Date, value: Double)]
    let unit: String

    var body: some View {
        let peak = hours.max { $0.value < $1.value }
        Chart {
            ForEach(hours, id: \.start) { hour in
                BarMark(x: .value("Hour", hour.start, unit: .hour), y: .value("Energy", hour.value), width: .ratio(0.6))
                    .foregroundStyle(hour.start == peak?.start ? Color.orange : Color.yellow)
                    .clipShape(.capsule)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        if hour.start == peak?.start {
                            Text(hourText(hour.start))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.orange, in: .capsule)
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisValueLabel { value.as(Date.self).map { Text(hourText($0)) } }
            }
        }
        .chartYAxis {
            AxisMarks { _ in AxisGridLine() }
        }
        .frame(height: 240)
        .padding(.top, 28)
        .accessibilityLabel("Electricity each hour over the last 24 hours")
    }
}

// MARK: Network

private struct NetworkFiche: View {
    @Environment(HomeStore.self) private var store
    let score: NetworkScore?
    let hasSource: Bool
    @State private var tab: Tab = .internet
    @State private var router = RouterReadings()

    enum Tab: Hashable { case internet, throughput, devices }

    var body: some View {
        if let score {
            VStack(alignment: .leading, spacing: 18) {
                let (status, color) = health(score.percent)
                FicheHeader(
                    value: "\(score.percent)",
                    unit: "%",
                    origin: .measured,
                    caption: String(localized: "last 24 hours"),
                    status: status,
                    statusColor: color,
                    detail: score.outages.isEmpty
                        ? String(localized: "No outage")
                        : String(localized: "\(score.outages.count) outage")
                )
                if tabs.count > 1 {
                    PillPicker(options: tabs, selection: $tab)
                }
                switch tab {
                case .internet:
                    if !score.latency.isEmpty {
                        LatencyChart(score: score)
                    }
                case .throughput:
                    ThroughputChart(points: router.download, unit: router.downloadUnit ?? "")
                case .devices:
                    if let count = router.connectedDevices {
                        StatTile(symbol: "laptopcomputer.and.iphone", title: String(localized: "Connected Devices"), value: "\(count)", unit: String(localized: "connected"))
                    }
                }
                if let added = InternetCheckSetting.addedAt, Date.now.timeIntervalSince(added) < 7 * 86_400 {
                    Label(
                        "Maison switched on an internet check on your server \(added.formatted(.relative(presentation: .named))).",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                }
                if let download = router.download.last {
                    HStack(spacing: 12) {
                        StatTile(symbol: "arrow.down.circle.fill", title: String(localized: "Internet Box"),
                                 value: download.value.formatted(.number.precision(.fractionLength(0...1))), unit: router.downloadUnit ?? "")
                        if let count = router.connectedDevices {
                            StatTile(symbol: "laptopcomputer.and.iphone", title: String(localized: "Devices"), value: "\(count)", unit: String(localized: "connected"))
                        }
                    }
                }
                HStack(spacing: 12) {
                    StatTile(
                        symbol: "checkmark.circle.fill",
                        title: String(localized: "Available"),
                        value: (score.availability * 100).formatted(.number.precision(.fractionLength(0...1))),
                        unit: "%"
                    )
                    if let last = score.latency.last {
                        StatTile(
                            symbol: "stopwatch.fill",
                            title: String(localized: "Response"),
                            value: last.milliseconds.formatted(.number.precision(.fractionLength(0))),
                            unit: "ms"
                        )
                    }
                }
            }
            .task { router = await store.routerReadings(since: .now.addingTimeInterval(-86_400)) }
        } else if hasSource {
            MissingScore(
                symbol: "wifi",
                title: "Measuring",
                message: "Your server checks the internet regularly. The score appears with the first readings."
            )
        } else if store.currentUser?.isAdmin == false {
            MissingScore(
                symbol: "wifi",
                title: "Waiting for an Administrator",
                message: "Maison switches on the internet check on your server by itself, with an administrator's account. It starts the next time an administrator opens Maison."
            )
        } else {
            MissingScore(
                symbol: "wifi",
                title: "Switching On the Internet Check",
                message: "Maison is setting up an internet check on your server. If it can't, it tries again tomorrow."
            )
        }
    }
}

private extension NetworkFiche {
    /// Only the tabs that have something to show.
    var tabs: [(value: Tab, title: LocalizedStringKey, symbol: String?)] {
        var tabs: [(value: Tab, title: LocalizedStringKey, symbol: String?)] = [(.internet, "Internet", nil)]
        if !router.download.isEmpty { tabs.append((.throughput, "Throughput", nil)) }
        if router.connectedDevices != nil { tabs.append((.devices, "Devices", nil)) }
        return tabs
    }
}

private struct LatencyChart: View {
    let score: NetworkScore

    var body: some View {
        Chart {
            if let usual = score.usualLatency {
                RectangleMark(
                    xStart: .value("Start", score.latency.first!.date),
                    xEnd: .value("End", score.latency.last!.date),
                    yStart: .value("Low", usual.lowerBound),
                    yEnd: .value("High", usual.upperBound)
                )
                .foregroundStyle(Color.green.opacity(0.12))
            }
            ForEach(score.outages, id: \.start) { outage in
                RectangleMark(xStart: .value("Start", outage.start), xEnd: .value("End", max(outage.end, outage.start.addingTimeInterval(900))))
                    .foregroundStyle(Color.orange.opacity(0.25))
                    .annotation(position: .top, spacing: 4) {
                        Text("Outage at \(outage.start.formatted(date: .omitted, time: .shortened)), \(Attention.minutes(outage.duration))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange, in: .capsule)
                            .fixedSize()
                    }
            }
            ForEach(score.latency, id: \.date) { point in
                LineMark(x: .value("Time", point.date), y: .value("Response", point.milliseconds))
                    .foregroundStyle(Color.cyan)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisValueLabel { value.as(Date.self).map { Text(hourText($0)) } }
            }
        }
        .chartYAxis {
            AxisMarks { _ in AxisGridLine() }
        }
        .frame(height: 240)
        .padding(.top, 28)
        .accessibilityLabel("Internet response time over the last 24 hours")
    }
}

private struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
            NumberLabel(value: value, unit: unit)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Comfort extras

/// What the Comfort fiche shows besides the score, with or without one: when to air, the room that
/// left its range, the air and the weather. With no sensor at all, this is still there.
private struct ComfortExtras: View {
    @Environment(HomeStore.self) private var store
    let score: ComfortScore?

    var body: some View {
        let outdoor = store.outdoorWeather
        let carbonDioxide = store.roomCarbonDioxide
        VStack(alignment: .leading, spacing: 14) {
            if let advice = AiringAdvice.compute(outdoor: outdoor, carbonDioxide: carbonDioxide) {
                AiringCard(advice: advice)
            }
            if let room = score?.rooms.first(where: { $0.excursion != nil }), let range = score?.range {
                RoomExcursionCard(room: room, range: range)
            }
            let worstAir = carbonDioxide.max { $0.ppm < $1.ppm }
            if worstAir != nil || outdoor != nil {
                HStack(spacing: 12) {
                    if let worstAir {
                        StatTile(symbol: "aqi.medium", title: String(localized: "Air, \(worstAir.room)"),
                                 value: worstAir.ppm.formatted(.number.precision(.fractionLength(0))), unit: "ppm")
                    }
                    if let outdoor {
                        StatTile(symbol: "cloud.sun.fill", title: String(localized: "Outside, weather"),
                                 value: degrees(outdoor.temperature), unit: "°")
                    }
                }
            }
        }
    }
}

/// "Air for 10 minutes now", and a reminder in an hour when now isn't convenient.
private struct AiringCard: View {
    let advice: AiringAdvice
    @State private var reminded = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "fan.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.orange, in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Comfort, weather").font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                Text("Air for 10 minutes now").font(.roundedHeadline)
                Text(detail).font(.roundedFootnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(reminded ? String(localized: "Reminded") : String(localized: "Remind Me")) {
                Task { reminded = await Self.remind() }
            }
            .font(.roundedSubheadlineEmphasized)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.blue.opacity(0.12), in: .capsule)
            .foregroundStyle(.blue)
            .buttonStyle(.plain)
            .disabled(reminded)
        }
        .padding(16)
        .cardStyle()
    }

    private var detail: String {
        let outside = degrees(advice.outdoor.temperature)
        switch advice.reason {
        case .carbonDioxide(let room, _): return String(localized: "\(outside)° outside, the CO₂ is rising in \(room)")
        case .mildOutside: return String(localized: "\(outside)° and dry outside")
        }
    }

    /// A local notification in an hour; nothing leaves the iPhone.
    private static func remind() async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to air")
        content.body = String(localized: "Open the windows for 10 minutes.")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        return (try? await center.add(UNNotificationRequest(identifier: "airing", content: content, trigger: trigger))) != nil
    }
}

/// The room that left its range, its temperature then, and its last day.
private struct RoomExcursionCard: View {
    let room: ComfortScore.Room
    let range: ClosedRange<Double>

    var body: some View {
        let excursion = room.excursion!
        VStack(alignment: .leading, spacing: 10) {
            Label(room.name, systemImage: Area(id: room.id, name: room.name).symbol)
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    NumberLabel(value: room.excursionValue.map(degrees) ?? "–", unit: String(localized: "° around \(hourText(excursion.interval.start))"))
                    Label(excursion.side == .tooWarm ? String(localized: "Too warm") : String(localized: "Too cold"),
                          systemImage: "exclamationmark.triangle")
                        .labelStyle(.compact)
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 12)
                Chart {
                    RectangleMark(yStart: .value("Low", range.lowerBound), yEnd: .value("High", range.upperBound))
                        .foregroundStyle(Color.green.opacity(0.10))
                    ForEach(room.readings, id: \.date) { reading in
                        LineMark(x: .value("Time", reading.date), y: .value("Temperature", reading.value))
                            .foregroundStyle(Color.orange)
                            .interpolationMethod(.stepEnd)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 150, height: 56)
            }
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Energy extras

/// What the Energy fiche reads besides the score: price and cost, devices, water.
private struct EnergyExtrasData: Equatable {
    var price: EnergyPrice?
    var cost: EnergyCost?
    var devices: [DeviceEnergy] = []
    var water: (value: Double, unit: String)?

    static func == (lhs: EnergyExtrasData, rhs: EnergyExtrasData) -> Bool {
        lhs.price == rhs.price && lhs.cost == rhs.cost && lhs.devices == rhs.devices
            && lhs.water?.value == rhs.water?.value && lhs.water?.unit == rhs.water?.unit
    }

    @MainActor
    static func load(store: HomeStore, score: EnergyScore) async -> EnergyExtrasData {
        var data = EnergyExtrasData()
        data.price = await store.energyPrice()
        if let price = data.price {
            data.cost = EnergyCost.compute(hourly: score.history, price: price.price(atHour:), day: score.day, asOf: score.asOf)
        }
        let meters = await store.electricityMeters().ids
        data.devices = await store.deviceEnergy(day: score.day, asOf: score.asOf, excluding: meters)
        data.water = await store.waterUsed(since: score.day)
        return data
    }
}

private struct DeviceEnergyList: View {
    let devices: [DeviceEnergy]
    let unit: String

    var body: some View {
        let peak = max(devices.first?.kilowattHours ?? 1, 0.001)
        VStack(spacing: 18) {
            ForEach(devices) { device in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(device.name).font(.roundedHeadline)
                        Spacer()
                        Text("\(device.kilowattHours.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                            .font(.roundedFootnote)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.gaugeTrack)
                            Capsule().fill(Color.yellow).frame(width: proxy.size.width * device.kilowattHours / peak)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}

/// The device that used the most, as in the mock-up's water heater card.
private struct TopDeviceCard: View {
    let device: DeviceEnergy
    let unit: String
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(device.name, systemImage: "bolt.fill")
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
            NumberLabel(value: device.kilowattHours.formatted(.number.precision(.fractionLength(0...1))),
                        unit: isToday ? String(localized: "\(unit) today") : String(localized: "\(unit) yesterday"))
            OriginTag(origin: .measured)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// The day's cost and the month at the same pace, or what's missing to show them.
private struct CostTiles: View {
    let cost: EnergyCost?
    let price: EnergyPrice?
    let isToday: Bool
    let addPrice: () -> Void

    var body: some View {
        if let cost, let price {
            HStack(spacing: 12) {
                StatTile(symbol: "number", title: isToday ? String(localized: "Estimated cost") : String(localized: "Yesterday’s cost"),
                         value: cost.day.formatted(.number.precision(.fractionLength(2))), unit: price.currency.currencySymbol)
                if let month = cost.monthProjection {
                    StatTile(symbol: "calendar", title: String(localized: "Month, estimated"),
                             value: month.formatted(.number.precision(.fractionLength(0))), unit: price.currency.currencySymbol)
                }
            }
        } else {
            Button(action: addPrice) {
                HStack(spacing: 14) {
                    Image(systemName: "number")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.yellow, in: .rect(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cost of the day").font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                        Text("Add your kWh price to see the cost").font(.roundedHeadline).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Text("Add")
                        .font(.roundedSubheadlineEmphasized)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.12), in: .capsule)
                        .foregroundStyle(.blue)
                }
                .padding(16)
                .cardStyle()
            }
            .buttonStyle(.pressable)
        }
    }
}

// MARK: - Network extras

private struct ThroughputChart: View {
    let points: [(date: Date, value: Double)]
    let unit: String

    var body: some View {
        Chart {
            ForEach(points, id: \.date) { point in
                LineMark(x: .value("Time", point.date), y: .value("Throughput", point.value))
                    .foregroundStyle(Color.cyan)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisValueLabel { value.as(Date.self).map { Text(hourText($0)) } }
            }
        }
        .chartYAxis {
            AxisMarks { _ in AxisGridLine() }
        }
        .frame(height: 200)
        .accessibilityLabel("Internet throughput over the last 24 hours, in \(unit)")
    }
}
