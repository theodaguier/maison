import Charts
import SwiftUI

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
                    ScoreRing(kind: kind, percent: kind.percent(in: scores), isLoading: scores == nil)
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
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 8) {
            ProgressRing(progress: Double(percent ?? 0) / 100, color: kind.color, lineWidth: 12) {
                if let percent {
                    NumberLabel(value: "\(percent)", unit: "%", size: .small, unitStyle: AnyShapeStyle(.primary))
                        .contentTransition(.numericText(value: Double(percent)))
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
        .accessibilityValue(percent.map { "\($0) %" } ?? String(localized: "Not measured yet"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The one thing to look at today. Safety would come first; for now, the weakest score's reason.
struct Attention: Equatable {
    let kind: ScoreKind
    let title: String
    let detail: String

    static func pick(from scores: HomeScores?) -> Attention? {
        guard let scores else { return nil }
        if let outage = scores.network?.outages.max(by: { $0.duration < $1.duration }) {
            return Attention(
                kind: .network,
                title: String(localized: "The internet dropped at \(outage.start.formatted(date: .omitted, time: .shortened))"),
                detail: String(localized: "Cut for \(Self.minutes(outage.duration))")
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
        if let energy = scores.energy, let difference = energy.difference, difference > 0.1 {
            return Attention(
                kind: .energy,
                title: String(localized: "More electricity than usual today"),
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
            result.append(difference < 0
                ? String(localized: "Energy: \(percent) % under your habit so far.")
                : String(localized: "Energy: \(percent) % over your habit so far."))
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

    enum Tab: Hashable { case rooms, temperature, humidity }

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
                    detail: "\(degrees(score.range.lowerBound)) – \(degrees(score.range.upperBound))°"
                )
                PillPicker(options: [(.rooms, "Rooms", nil), (.temperature, "Temperature", nil), (.humidity, "Humidity", nil)], selection: $tab)
                switch tab {
                case .rooms:
                    VStack(spacing: 20) {
                        ForEach(score.rooms) { RoomComfortRow(room: $0) }
                    }
                case .temperature:
                    RoomValues(deviceClass: "temperature", unit: "°", range: score.range)
                case .humidity:
                    RoomValues(deviceClass: "humidity", unit: " %", range: 40...60)
                }
                RangeRow(range: score.range, origin: score.rangeOrigin) { editsRange = true }
            }
            .sheet(isPresented: $editsRange) { ComfortRangeEditor(range: score.range) }
        } else if store.roomTemperatureSensors.isEmpty {
            MissingScore(
                symbol: "thermometer.medium.slash",
                title: "No Temperature in Your Rooms",
                message: "Comfort counts the time each room spends in your range. Add a temperature sensor to a room in Home Assistant, or assign an existing one to its room."
            )
        } else {
            VStack(spacing: 14) {
                MissingScore(
                    symbol: "calendar.badge.clock",
                    title: "Learning Your Range",
                    message: "Maison needs three days of readings to learn the temperatures you live in. You can set your range now instead."
                )
                Button("Set My Range") { editsRange = true }
                    .buttonStyle(.glassProminent)
            }
            .sheet(isPresented: $editsRange) { ComfortRangeEditor(range: 19...22) }
        }
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
                    Text(origin == .entered ? String(localized: "Set by you") : String(localized: "Learned from your past week"))
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

    var body: some View {
        if let score {
            VStack(alignment: .leading, spacing: 18) {
                FicheHeader(
                    value: score.today.formatted(.number.precision(.fractionLength(0...1))),
                    unit: score.unit,
                    origin: .measured,
                    caption: String(localized: "since midnight"),
                    status: status.0,
                    statusColor: status.1,
                    detail: detail
                )
                if !score.lastDay.isEmpty {
                    EnergyChart(hours: score.lastDay, unit: score.unit)
                }
                if score.usual == nil {
                    MissingScore(
                        symbol: "calendar.badge.clock",
                        title: "Learning Your Habit",
                        message: "The score compares today with the same hours of your previous days. It appears after three days of readings."
                    )
                }
            }
        } else {
            MissingScore(
                symbol: "bolt.slash",
                title: "No Electricity Meter",
                message: "Energy compares today's electricity with your habit. Add your meter to Home Assistant's Energy dashboard, then come back here."
            )
        }
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
    @Environment(\.openURL) private var openURL
    let score: NetworkScore?
    let hasSource: Bool

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
                if !score.latency.isEmpty {
                    LatencyChart(score: score)
                }
                HStack(spacing: 12) {
                    StatTile(
                        symbol: "checkmark.circle.fill",
                        title: "Available",
                        value: (score.availability * 100).formatted(.number.precision(.fractionLength(0...1))),
                        unit: "%"
                    )
                    if let last = score.latency.last {
                        StatTile(
                            symbol: "stopwatch.fill",
                            title: "Response",
                            value: last.milliseconds.formatted(.number.precision(.fractionLength(0))),
                            unit: "ms"
                        )
                    }
                }
            }
        } else if hasSource {
            MissingScore(
                symbol: "wifi.exclamationmark",
                title: "No Reading Today",
                message: "Home Assistant's internet check hasn't reported anything in the last 24 hours."
            )
        } else {
            VStack(spacing: 14) {
                MissingScore(
                    symbol: "wifi",
                    title: "Nothing Checks Your Internet Yet",
                    message: "Home Assistant's Ping integration checks the connection every minute. Add it once, pointed at a public address such as 1.1.1.1, and the Network score starts the same day."
                )
                if let serverURL = store.serverURL {
                    Button("Add Ping in Home Assistant") {
                        openURL(serverURL.appending(path: "config/integrations/dashboard/add").appending(queryItems: [URLQueryItem(name: "domain", value: "ping")]))
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
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
    let title: LocalizedStringKey
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
