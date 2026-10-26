import SwiftUI

// The home screen under the rings: one section per score, each with its number, a picture of the day
// and what Maison understood, then the shortcuts the person pinned. The person chooses which sections
// show and in what order.

/// Where touching something on the home leads.
enum HomeDestination: Equatable {
    case score(ScoreKind)
    case finding(Finding)
    case device(String)
    case sources
}

// MARK: - Wording of a highlight

extension Highlight {
    var kind: ScoreKind { ScoreKind(rawValue: score.rawValue) ?? .energy }

    var title: String {
        switch fact {
        case .finding(let finding):
            finding.title
        case .outage(let start, _):
            String(localized: "The internet dropped at \(start.formatted(date: .omitted, time: .shortened))")
        case .roomOutOfRange(let room, let side, let start, _):
            side == .tooWarm
                ? String(localized: "\(room) was too warm around \(hourText(start))")
                : String(localized: "\(room) was too cold around \(hourText(start))")
        case .heatingWhileAway:
            String(localized: "The heating runs with nobody home")
        case .coolingWhileAway:
            String(localized: "The air conditioning runs with nobody home")
        case .windowOpenWhileHeating(let window, _):
            String(localized: "\(window) is open while the heating runs")
        case .windowOpenWhileCooling(let window, _):
            String(localized: "\(window) is open while the air conditioning runs")
        case .airNow(let room, _):
            String(localized: "The air is stale in \(room)")
        case .mildOutside:
            String(localized: "A good moment to air")
        case .energyAboveHabit(_, let isToday):
            isToday ? String(localized: "More electricity than usual today") : String(localized: "More electricity than usual yesterday")
        case .topDevice(_, let name, let share, _, let isToday):
            isToday
                ? String(localized: "\(name): \(Int((share * 100).rounded())) % of your electricity today")
                : String(localized: "\(name): \(Int((share * 100).rounded())) % of your electricity yesterday")
        case .alwaysOn(let watts, _, _):
            String(localized: "\(Int(watts.rounded())) W never switch off")
        case .monthCost(let amount, let currency):
            String(localized: "About \(amount.formatted(.number.precision(.fractionLength(0)))) \(currency.currencySymbol) this month")
        case .connectedDevices(let count):
            String(localized: "\(count) devices on your network")
        case .missingMeter:
            String(localized: "Your meter can talk to Maison")
        case .missingTariff:
            String(localized: "Enter your tariff")
        case .missingThermometer:
            String(localized: "A thermometer gives the Comfort score")
        }
    }

    var detail: String {
        switch fact {
        case .finding(let finding):
            String(localized: "About \(finding.yearlyValue.formatted(.number.precision(.fractionLength(0)))) \(finding.currency.currencySymbol) more a year")
        case .outage(_, let duration):
            String(localized: "Cut for \(Highlight.minutes(duration))")
        case .roomOutOfRange(_, _, _, let percent):
            String(localized: "\(percent) % of the day in your range")
        case .heatingWhileAway, .coolingWhileAway:
            String(localized: "Turn it off until someone is back")
        case .windowOpenWhileHeating:
            String(localized: "The heat goes outside")
        case .windowOpenWhileCooling:
            String(localized: "The cool air goes outside")
        case .airNow(_, let ppm):
            String(localized: "CO₂ at \(Int(ppm.rounded())) ppm, air for a few minutes")
        case .mildOutside(let temperature):
            String(localized: "\(EntityState.degrees(temperature)) outside, and dry")
        case .energyAboveHabit(let difference, _):
            String(localized: "\(Int((difference * 100).rounded())) % over your habit")
        case .topDevice(_, _, _, let kilowattHours, _):
            String(localized: "\(kilowattHours.formatted(.number.precision(.fractionLength(0...1)))) kWh, measured by its plug")
        case .alwaysOn(_, let yearlyCost, let currency):
            yearlyCost.map { String(localized: "Even at night, about \($0.formatted(.number.precision(.fractionLength(0)))) \(currency.currencySymbol) a year") }
                ?? String(localized: "Even at night, read on your meter")
        case .monthCost:
            String(localized: "At this month’s pace")
        case .connectedDevices:
            String(localized: "Seen by your box right now")
        case .missingMeter:
            String(localized: "A small reader, then nothing to set up")
        case .missingTariff:
            String(localized: "To see what your electricity costs")
        case .missingThermometer:
            String(localized: "Maison adds it as soon as it’s on your network")
        }
    }

    /// What needs a look says it in its score's deeper colour; the rest stays quiet.
    var isPressing: Bool { rank == .now || rank == .worth || rank == .today }

    /// A source still missing carries no value, so no origin to show.
    var showsOrigin: Bool { rank != .missing }

    var destination: HomeDestination {
        switch fact {
        case .finding(let finding): .finding(finding)
        case .topDevice(let entityID, _, _, _, _): .device(entityID)
        case .missingThermometer: .sources
        default: .score(kind)
        }
    }

    /// The climates its button turns off, when the button acts rather than opens.
    var climatesToTurnOff: [String] {
        switch fact {
        case .heatingWhileAway(let ids), .coolingWhileAway(let ids),
             .windowOpenWhileHeating(_, let ids), .windowOpenWhileCooling(_, let ids): ids
        default: []
        }
    }

    /// Whether its button does more than open the score's fiche, which the section's header already does.
    var hasOwnAction: Bool {
        if !climatesToTurnOff.isEmpty { return true }
        switch destination {
        case .score: return [.missingMeter, .missingTariff].contains(fact)
        default: return true
        }
    }

    var actionTitle: String {
        if !climatesToTurnOff.isEmpty { return String(localized: "Turn Off") }
        switch fact {
        case .finding: return String(localized: "Fix")
        case .missingMeter, .missingTariff, .missingThermometer: return String(localized: "Add")
        default: return String(localized: "See")
        }
    }

    /// Facts a section of their own shows, when it is on the home.
    var ownSection: HomeSection? {
        switch fact {
        case .airNow, .mildOutside: .weather
        case .monthCost, .missingTariff: .monthCost
        default: nil
        }
    }

    static func minutes(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}

extension HomeSection {
    var title: String {
        switch self {
        case .summary: String(localized: "Day Summary")
        case .shortcuts: String(localized: "Shortcuts")
        case .comfort: ScoreKind.comfort.title
        case .energy: ScoreKind.energy.title
        case .network: ScoreKind.network.title
        case .weather: String(localized: "Weather and Airing")
        case .monthCost: String(localized: "Month’s Cost")
        }
    }

    var symbol: String {
        switch self {
        case .summary: "leaf.fill"
        case .shortcuts: "square.grid.2x2.fill"
        case .comfort: ScoreKind.comfort.symbol
        case .energy: ScoreKind.energy.symbol
        case .network: ScoreKind.network.symbol
        case .weather: "cloud.sun.fill"
        case .monthCost: "eurosign"
        }
    }

    var kind: ScoreKind? { score.flatMap { ScoreKind(rawValue: $0.rawValue) } }

    /// The one thing this section says, out of what Maison noticed.
    func highlight(in highlights: [Highlight]) -> Highlight? {
        guard let score else { return nil }
        return highlights.first { highlight in
            guard highlight.score == score else { return false }
            if let own = highlight.ownSection { return own == self }
            return self == .comfort || self == .energy || self == .network
        }
    }
}

// MARK: - A score's section

/// The frame every section shares: which score, the way into its fiche, then its content and what Maison understood.
struct HomeSectionCard<Content: View>: View {
    @Environment(HomeStore.self) private var store
    let section: HomeSection
    let highlight: Highlight?
    let open: (HomeDestination) -> Void
    @ViewBuilder let content: Content
    @State private var turnedOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                if let kind = section.kind { open(.score(kind)) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: section.symbol)
                        .foregroundStyle(section.kind?.color ?? .secondary)
                    Text(section.title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .font(.roundedSubheadlineEmphasized)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            content
            if let highlight {
                Theme.separator.frame(height: 1)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(highlight.title)
                            .font(.roundedHeadline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(highlight.detail)
                                .font(.roundedFootnote)
                                .foregroundStyle(highlight.isPressing ? AnyShapeStyle(highlight.kind.deep) : AnyShapeStyle(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                            if highlight.showsOrigin { OriginTag(origin: highlight.origin) }
                        }
                    }
                    Spacer(minLength: 0)
                    if highlight.hasOwnAction {
                        Button {
                            act(on: highlight)
                        } label: {
                            if turnedOff {
                                Image(systemName: "checkmark")
                            } else {
                                Text(highlight.actionTitle)
                            }
                        }
                        .font(.roundedSubheadlineEmphasized)
                        .buttonStyle(.glassProminent)
                        .disabled(turnedOff)
                        .sensoryFeedback(.success, trigger: turnedOff)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func act(on highlight: Highlight) {
        guard !highlight.climatesToTurnOff.isEmpty else { return open(highlight.destination) }
        Task {
            for id in highlight.climatesToTurnOff {
                if let climate = store.states[id] { await store.call("climate", "turn_off", on: climate) }
            }
            turnedOff = true
        }
    }
}

/// The numbers behind a score, side by side, so the section says it all without opening the fiche.
struct SectionStats: View {
    let items: [(value: String, label: String)]

    var body: some View {
        if !items.isEmpty { row }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Theme.separator.frame(width: 1, height: 36).padding(.horizontal, 12) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.value)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.label)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short line in place of the number, when the score can't be computed yet.
private struct SectionWaiting: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.roundedSubheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A source the score needs, and the way to add it.
private struct MissingSource: View {
    let text: String
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Add", action: add)
                .font(.roundedSubheadlineEmphasized)
                .buttonStyle(.glassProminent)
        }
    }
}

struct ComfortSection: View {
    @Environment(HomeStore.self) private var store
    let scores: HomeScores?
    let highlight: Highlight?
    let open: (HomeDestination) -> Void

    var body: some View {
        HomeSectionCard(section: .comfort, highlight: highlight, open: open) {
            if let comfort = scores?.comfort {
                let (status, color) = health(comfort.percent, kind: .comfort)
                FicheHeader(
                    value: "\(comfort.percent)", unit: "%", origin: .measured,
                    caption: String(localized: "last 24 hours"), status: status, statusColor: color,
                    detail: "\(EntityState.degrees(comfort.range.lowerBound)) – \(EntityState.degrees(comfort.range.upperBound))"
                )
                RoomRanges(range: comfort.range, rooms: store.comfortSensors.compactMap { room in
                    room.sensor.numericState.map { (room.id, room.name, $0) }
                })
            } else if scores != nil, store.comfortSensors.isEmpty {
                MissingSource(text: String(localized: "No thermometer reaches your server yet. One in a room gives this score.")) { open(.sources) }
            } else if scores != nil, highlight == nil {
                SectionWaiting(text: String(localized: "Waiting for the first readings of your thermometers."))
            }
        }
    }
}

/// Each room's temperature against the household's range.
struct RoomRanges: View {
    let range: ClosedRange<Double>
    let rooms: [(id: String, name: String, value: Double)]

    var body: some View {
        let scale = HomeVisuals.scale(range: range, values: rooms.map(\.value))
        VStack(spacing: 12) {
            ForEach(rooms, id: \.id) { room in
                let inside = range.contains(room.value)
                HStack(spacing: 12) {
                    Text(room.name)
                        .font(.roundedSubheadlineEmphasized)
                        .lineLimit(1)
                        .frame(width: 104, alignment: .leading)
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let low = HomeVisuals.position(of: range.lowerBound, on: scale) * width
                        let high = HomeVisuals.position(of: range.upperBound, on: scale) * width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.gaugeTrack).frame(height: 8)
                            Capsule().fill(Theme.good.opacity(0.3)).frame(width: high - low, height: 8).offset(x: low)
                            Circle()
                                .fill(inside ? Theme.good : ScoreKind.comfort.deep)
                                .overlay(Circle().stroke(Theme.card, lineWidth: 3))
                                .frame(width: 16, height: 16)
                                .offset(x: HomeVisuals.position(of: room.value, on: scale) * width - 8)
                        }
                        .frame(height: 16)
                    }
                    .frame(height: 16)
                    Text(EntityState.degrees(room.value))
                        .font(.roundedSubheadlineEmphasized)
                        .monospacedDigit()
                        .foregroundStyle(inside ? AnyShapeStyle(.secondary) : AnyShapeStyle(ScoreKind.comfort.deep))
                        .frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(room.name)
                .accessibilityValue(EntityState.degrees(room.value))
            }
        }
    }
}

struct EnergySection: View {
    @Environment(HomeStore.self) private var store
    let scores: HomeScores?
    let highlight: Highlight?
    let open: (HomeDestination) -> Void

    var body: some View {
        HomeSectionCard(section: .energy, highlight: highlight, open: open) {
            if let energy = scores?.energy {
                let status = Self.status(energy)
                FicheHeader(
                    value: energy.today.formatted(.number.precision(.fractionLength(0...1))), unit: energy.unit, origin: .measured,
                    caption: Calendar.current.isDateInToday(energy.day) ? String(localized: "since midnight") : String(localized: "yesterday, whole day"),
                    status: status.0, statusColor: status.1, detail: Self.detail(energy)
                )
                if !energy.lastDay.isEmpty {
                    EnergyChart(hours: energy.lastDay, unit: energy.unit, offPeak: scores?.energyPrice?.tariff?.offPeak, height: 150)
                }
                SectionStats(items: Self.stats(energy, scores: scores))
            } else if scores?.hasElectricityMeter == false {
                MissingSource(text: String(localized: "No meter is connected yet. Maison can read it with a small reader, or from your grid operator.")) { open(.score(.energy)) }
            } else if scores != nil, highlight == nil {
                SectionWaiting(text: String(localized: "Waiting for the first readings of your meter."))
            }
        }
    }

    static func stats(_ score: EnergyScore, scores: HomeScores?) -> [(value: String, label: String)] {
        var items: [(value: String, label: String)] = []
        if let usual = score.usual {
            items.append(("\(usual.formatted(.number.precision(.fractionLength(0...1)))) \(score.unit)", String(localized: "Usually")))
        }
        if let cost = scores?.energyCost, let price = scores?.energyPrice {
            let symbol = price.currency.currencySymbol
            items.append(("\(cost.day.formatted(.number.precision(.fractionLength(2)))) \(symbol)", Calendar.current.isDateInToday(score.day) ? String(localized: "Today") : String(localized: "Yesterday")))
            if let month = cost.monthProjection {
                items.append(("\(month.formatted(.number.precision(.fractionLength(0)))) \(symbol)", String(localized: "This Month")))
            }
        }
        return items
    }

    static func status(_ score: EnergyScore) -> (String, Color) {
        guard let percent = score.percent else { return (String(localized: "Measuring"), .secondary) }
        switch percent {
        case 75...: return (String(localized: "Frugal"), Theme.good)
        case 50...: return (String(localized: "Usual"), .secondary)
        default: return (String(localized: "High"), ScoreKind.energy.deep)
        }
    }

    static func detail(_ score: EnergyScore) -> String {
        guard let difference = score.difference else { return String(localized: "No habit yet") }
        let percent = Int((abs(difference) * 100).rounded())
        return difference < 0 ? String(localized: "\(percent) % under your habit") : String(localized: "\(percent) % over your habit")
    }
}

struct NetworkSection: View {
    @Environment(HomeStore.self) private var store
    let scores: HomeScores?
    let highlight: Highlight?
    let open: (HomeDestination) -> Void

    var body: some View {
        HomeSectionCard(section: .network, highlight: highlight, open: open) {
            if let network = scores?.network, let computedAt = scores?.computedAt {
                let (status, color) = health(network.percent, kind: .network)
                FicheHeader(
                    value: "\(network.percent)", unit: "%", origin: .measured,
                    caption: String(localized: "over 24 h"), status: status, statusColor: color,
                    detail: Self.detail(network)
                )
                SectionStats(items: Self.stats(network, router: router))
                let window = DateInterval(start: computedAt.addingTimeInterval(-86_400), end: computedAt)
                AvailabilityRibbon(
                    slices: HomeVisuals.availability(outages: network.outages, known: network.latency.first.map { DateInterval(start: min($0.date, window.start), end: window.end) } ?? window, window: window),
                    window: window
                )
            } else if scores != nil, highlight == nil {
                SectionWaiting(text: scores?.hasNetworkSource == true
                    ? String(localized: "Your server checks the internet regularly. The score appears with the first readings.")
                    : String(localized: "Maison switches on an internet check on your server by itself."))
            }
        }
    }

    /// What the box measures right now: its throughput and the devices it sees.
    private var router: (download: String?, devices: Int?) {
        let rates = store.devices.filter { $0.deviceClass == "data_rate" && $0.numericState != nil }
        let download = rates.max { $0.numericState! < $1.numericState! }
            .map { "\($0.numericState!.formatted(.number.precision(.fractionLength(0...1)))) \($0.unit ?? "")" }
        let trackers = store.states.values.filter { $0.domain == "device_tracker" && $0.attributes["source_type"]?.stringValue == "router" }
        return (download, trackers.isEmpty ? nil : trackers.count { $0.state == "home" })
    }

    static func stats(_ score: NetworkScore, router: (download: String?, devices: Int?)) -> [(value: String, label: String)] {
        var items = [
            ((score.availability * 100).formatted(.number.precision(.fractionLength(0...1))) + " %", String(localized: "Available")),
            ("\(score.outages.count)", score.outages.count == 1 ? String(localized: "Outage") : String(localized: "Outages")),
        ]
        if let last = score.latency.last { items.append(("\(Int(last.milliseconds.rounded())) ms", String(localized: "Response"))) }
        if let download = router.download {
            items.append((download, String(localized: "Download")))
        } else if let devices = router.devices {
            items.append(("\(devices)", String(localized: "Devices")))
        }
        return items
    }

    static func detail(_ score: NetworkScore) -> String {
        guard let last = score.latency.last else {
            return score.outages.isEmpty ? String(localized: "No outage") : String(localized: "\(score.outages.count) outage")
        }
        let ms = Int(last.milliseconds.rounded())
        if let usual = score.usualLatency, usual.contains(last.milliseconds) { return String(localized: "\(ms) ms, as usual") }
        return String(localized: "\(ms) ms to answer")
    }
}

/// The last day, half-hour by half-hour: up in the score's colour, an outage deeper.
struct AvailabilityRibbon: View {
    let slices: [HomeVisuals.Slice]
    let window: DateInterval
    /// The half-hour under the finger.
    @State private var touched: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    Capsule()
                        .fill(color(slice))
                        .opacity(touched == nil || touched == index ? 1 : 0.4)
                        .frame(height: touched == index ? 36 : 30)
                }
            }
            .frame(height: 36)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .contentShape(.rect)
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in touched = index(at: value.location.x) }
                .onEnded { _ in touched = nil })
            .overlay(alignment: .top) {
                if let touched {
                    GeometryReader { proxy in
                        ChartCallout(time: sliceTime(touched), value: label(slices[touched]))
                            .position(x: min(max((Double(touched) + 0.5) / Double(slices.count) * proxy.size.width, 60), proxy.size.width - 60), y: -26)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: touched)
            HStack {
                Text(hourText(window.start))
                Spacer()
                Text(hourText(window.start.addingTimeInterval(window.duration / 2)))
                Spacer()
                Text("Now")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Internet over the last 24 hours")
        .accessibilityValue(slices.contains(.down) ? String(localized: "With an outage") : String(localized: "No outage"))
    }

    @State private var width: CGFloat = 1

    private func index(at x: CGFloat) -> Int {
        min(slices.count - 1, max(0, Int(x / max(width, 1) * CGFloat(slices.count))))
    }

    private func sliceTime(_ index: Int) -> String {
        let length = window.duration / Double(slices.count)
        let start = window.start.addingTimeInterval(Double(index) * length)
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(start.addingTimeInterval(length).formatted(date: .omitted, time: .shortened))"
    }

    private func label(_ slice: HomeVisuals.Slice) -> String {
        switch slice {
        case .up: String(localized: "Connected")
        case .down: String(localized: "Outage")
        case .unknown: String(localized: "No reading")
        }
    }

    private func color(_ slice: HomeVisuals.Slice) -> Color {
        switch slice {
        case .up: ScoreKind.network.color
        case .down: ScoreKind.network.deep
        case .unknown: Theme.gaugeTrack
        }
    }
}

struct WeatherSection: View {
    @Environment(HomeStore.self) private var store
    let highlight: Highlight?
    let open: (HomeDestination) -> Void

    var body: some View {
        HomeSectionCard(section: .weather, highlight: highlight, open: open) {
            if let outdoor = store.outdoorWeather {
                let advice = AiringAdvice.compute(outdoor: outdoor, carbonDioxide: store.roomCarbonDioxide)
                FicheHeader(
                    value: outdoor.temperature.formatted(.number.precision(.fractionLength(0...1))), unit: "°", origin: .measured,
                    caption: String(localized: "outside"),
                    status: advice == nil ? String(localized: "Keep Closed") : String(localized: "Good to Air"),
                    statusColor: advice == nil ? .secondary : Theme.good,
                    detail: outdoor.humidity.map { String(localized: "\(Int($0.rounded())) % humidity") } ?? ""
                )
            } else {
                SectionWaiting(text: String(localized: "Maison adds a weather service to your server by itself."))
            }
        }
    }
}

struct MonthCostSection: View {
    let scores: HomeScores?
    let highlight: Highlight?
    let open: (HomeDestination) -> Void

    var body: some View {
        HomeSectionCard(section: .monthCost, highlight: highlight?.fact == .missingTariff ? highlight : nil, open: open) {
            if let cost = scores?.energyCost, let price = scores?.energyPrice, let month = cost.monthProjection {
                FicheHeader(
                    value: month.formatted(.number.precision(.fractionLength(0))), unit: price.currency.currencySymbol, origin: .estimated,
                    caption: String(localized: "this month, at this pace"),
                    status: cost.day.formatted(.number.precision(.fractionLength(2))) + " " + price.currency.currencySymbol,
                    statusColor: .primary,
                    detail: String(localized: "so far today")
                )
            } else if highlight?.fact != .missingTariff {
                SectionWaiting(text: String(localized: "The month’s cost appears after three days of readings."))
            }
        }
    }
}

// MARK: - Shortcuts

/// The devices and scenes the person pinned, one tap each. Holding one opens it.
struct ShortcutsRow: View {
    @Environment(HomeStore.self) private var store
    let edit: () -> Void
    let openDevice: (String) -> Void
    @State private var done = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcuts").font(.roundedSubheadlineEmphasized).foregroundStyle(.secondary)
                Spacer()
                Button("Edit", action: edit).font(.roundedSubheadlineEmphasized)
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4), spacing: 16) {
                ForEach(store.favorites.prefix(8)) { entity in
                    Button {
                        Task {
                            await store.performPrimaryAction(on: entity)
                            done += 1
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: entity.symbolName)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(entity.isActive ? AnyShapeStyle(entity.accent) : AnyShapeStyle(.primary))
                                .frame(width: 60, height: 60)
                                .background(Theme.card, in: .circle)
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                            Text(entity.name)
                                .font(.roundedFootnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button("Open", systemImage: "slider.horizontal.3") { openDevice(entity.entityID) }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: done)
    }
}

/// Which devices and scenes are pinned, and in what order.
struct HomeFavoritesEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pinned: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pinned, id: \.self) { id in
                        if let entity = store.states[id] { row(entity) }
                    }
                    .onMove { pinned.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { pinned.remove(atOffsets: $0) }
                } header: {
                    Text("On the Home")
                } footer: {
                    Text("The first eight show on the home. Hold one there to open it.")
                }
                Section("Add") {
                    ForEach(candidates) { entity in
                        Button {
                            withAnimation { pinned.append(entity.entityID) }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                                row(entity)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        store.setFavorites(pinned)
                        dismiss()
                    }
                }
            }
            .onAppear { pinned = store.favorites.map(\.entityID) }
        }
    }

    /// Scenes first, then what can be switched in one tap.
    private var candidates: [EntityState] {
        let taken = Set(pinned)
        let scenes = store.scenes.filter { !taken.contains($0.entityID) }
        let devices = store.devices.filter { !taken.contains($0.entityID) && DeviceCommand(primaryActionFor: $0) != nil }.sortedByName()
        return scenes + devices
    }

    private func row(_ entity: EntityState) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name).font(.roundedHeadline).foregroundStyle(.primary)
                if let room = store.area(of: entity)?.name {
                    Text(room).font(.roundedFootnote).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: entity.symbolName).foregroundStyle(entity.accent)
        }
    }
}

// MARK: - Editing the home

struct HomeLayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var layout: HomeLayoutSetting
    @State private var draft = HomeLayoutSetting.standard

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(draft.shown) { section in
                        Label(section.title, systemImage: section.symbol)
                    }
                    .onMove { draft.shown.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.shown.remove(atOffsets: $0) }
                } header: {
                    Text("On the Home")
                } footer: {
                    Text("A section with something to fix moves to the top until it’s fixed, then goes back to its place.")
                }
                if !draft.hidden.isEmpty {
                    Section("Hidden") {
                        ForEach(draft.hidden) { section in
                            Button {
                                withAnimation { draft.shown.append(section) }
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                                    Label(section.title, systemImage: section.symbol).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        layout = draft
                        draft.save()
                        dismiss()
                    }
                }
            }
            .onAppear { draft = layout }
        }
    }
}
