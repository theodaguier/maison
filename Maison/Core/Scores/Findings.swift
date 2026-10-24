import Foundation

// Findings: something Maison noticed, why it thinks so, what it is worth, and the one tap that fixes it.
// The code computes every value; nothing here is worded by a model.

// MARK: - Tariff

/// The household's electricity tariff, as entered: one price, or peak and off-peak hours.
struct EnergyTariff: Codable, Equatable, Sendable {
    /// Base price, or the peak price with off-peak hours.
    var price: Double
    var offPeak: OffPeak?

    struct OffPeak: Codable, Equatable, Sendable {
        var price: Double
        /// Hours of the day, 0 to 23: off-peak from `startHour` to `endHour`, across midnight when needed.
        var startHour: Int
        var endHour: Int

        func contains(hour: Int) -> Bool {
            startHour <= endHour ? (startHour..<endHour).contains(hour) : hour >= startHour || hour < endHour
        }

        /// Off-peak hours in a day.
        var duration: Int { startHour <= endHour ? endHour - startHour : 24 - startHour + endHour }
    }

    /// The price of a kWh used during `hour`.
    func price(atHour hour: Int) -> Double {
        if let offPeak, offPeak.contains(hour: hour) { return offPeak.price }
        return price
    }

    static let key = "energyTariff"

    static func load(from defaults: UserDefaults = .standard) -> EnergyTariff? {
        if let data = defaults.data(forKey: key), let tariff = try? JSONDecoder().decode(EnergyTariff.self, from: data) { return tariff }
        // A single price entered before tariffs existed.
        return EnergyPriceSetting.price(in: defaults).map { EnergyTariff(price: $0) }
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

// MARK: - Findings

struct Finding: Identifiable, Equatable, Sendable {
    /// Stable across refreshes, so ignoring one sticks.
    let id: String
    let kind: ScoreKindID
    let title: String
    /// What fixing it is worth each year, in `currency`.
    let yearlyValue: Double
    let currency: String
    let reasons: [Reason]
    /// The device's use over the day the finding is about, by hour, for its timeline.
    let usage: [Int: Double]
    let offPeak: EnergyTariff.OffPeak?
    let deviceName: String
    /// The rule the main button creates; `nil` when nothing in the home can switch the device.
    let rule: AutomationRule?

    enum ScoreKindID: String, Sendable { case comfort, energy, network }

    struct Reason: Equatable, Sendable {
        let symbol: String
        let title: String
        let detail: String
        let origin: ValueOrigin
    }
}

/// Rules Maison created from a finding, by id, with when. Kept on the iPhone that created them.
enum ProposedRules {
    static let key = "rulesFromFindings"

    static func createdAt(_ ruleID: String, in defaults: UserDefaults = .standard) -> Date? {
        (defaults.dictionary(forKey: key)?[ruleID] as? Double).map { Date(timeIntervalSince1970: $0) }
    }

    static func add(_ ruleID: String, at date: Date = .now, in defaults: UserDefaults = .standard) {
        var rules = defaults.dictionary(forKey: key) ?? [:]
        rules[ruleID] = date.timeIntervalSince1970
        defaults.set(rules, forKey: key)
    }

    static func remove(_ ruleID: String, in defaults: UserDefaults = .standard) {
        var rules = defaults.dictionary(forKey: key) ?? [:]
        rules[ruleID] = nil
        defaults.set(rules, forKey: key)
    }
}

/// Things the person said about a finding: ignored, or wrong and why. Kept on the iPhone.
enum FindingFeedback {
    static let ignoredKey = "ignoredFindings"

    static func isIgnored(_ id: String, in defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: ignoredKey) ?? []).contains(id)
    }

    static func ignore(_ id: String, in defaults: UserDefaults = .standard) {
        defaults.set(Array(Set((defaults.stringArray(forKey: ignoredKey) ?? []) + [id])), forKey: ignoredKey)
    }
}

enum PeakHoursFinding {
    /// A device used at least this much in a day is worth moving.
    static let minimumDailyUse = 0.5
    /// And at least this share of it fell in peak hours.
    static let minimumPeakShare = 0.6

    /// A device that runs in peak hours when off-peak hours exist. `usage` is its kWh by hour of one day.
    static func compute(
        deviceID: String,
        deviceName: String,
        usage: [Int: Double],
        tariff: EnergyTariff,
        currency: String,
        switchEntity: String?
    ) -> Finding? {
        guard let offPeak = tariff.offPeak, offPeak.price < tariff.price else { return nil }
        let total = usage.values.reduce(0, +)
        let peak = usage.filter { !offPeak.contains(hour: $0.key) }.values.reduce(0, +)
        guard total >= minimumDailyUse, peak / total >= minimumPeakShare else { return nil }
        let extraPerDay = peak * (tariff.price - offPeak.price)
        let busiest = usage.max { $0.value < $1.value }?.key ?? 0

        var rule: AutomationRule?
        if let switchEntity {
            var proposal = AutomationRule.new()
            proposal.name = String(localized: "\(deviceName) in off-peak hours")
            proposal.description = String(localized: "Created by Maison: runs only during the off-peak hours of your tariff.")
            proposal.triggers = [.time(at: String(format: "%02d:00:00", offPeak.startHour))]
            proposal.actions = [
                .device(entityID: switchEntity, service: "switch.turn_on", data: [:]),
                .wait(minutes: offPeak.duration * 60),
                .device(entityID: switchEntity, service: "switch.turn_off", data: [:]),
            ]
            rule = proposal
        }

        return Finding(
            id: "peak-hours:\(deviceID)",
            kind: .energy,
            title: String(localized: "\(deviceName): mostly in peak hours"),
            yearlyValue: extraPerDay * 365,
            currency: currency,
            reasons: [
                Finding.Reason(
                    symbol: "clock.fill",
                    title: String(localized: "Most of it around \(busiest):00"),
                    detail: String(localized: "\(Int((peak / total * 100).rounded())) % of its use in peak hours"),
                    origin: .measured
                ),
                Finding.Reason(
                    symbol: "doc.text.fill",
                    title: String(localized: "Off-peak from \(offPeak.startHour):00 to \(offPeak.endHour):00"),
                    detail: String(localized: "your tariff"),
                    origin: .entered
                ),
                Finding.Reason(
                    symbol: "number",
                    title: String(localized: "\(extraPerDay.formatted(.number.precision(.fractionLength(2)))) \(currency.currencySymbol) more per day"),
                    detail: String(localized: "\(peak.formatted(.number.precision(.fractionLength(1)))) kWh at the peak price"),
                    origin: .estimated
                ),
            ],
            usage: usage,
            offPeak: offPeak,
            deviceName: deviceName,
            rule: rule
        )
    }
}

extension HomeStore {
    /// The switch that powers the same device as `entity` (a plug, a contactor), if any.
    func powerSwitch(for entity: EntityState) -> EntityState? {
        guard let device = layout.deviceByEntity[entity.entityID] else { return nil }
        return states.values.first { $0.domain == "switch" && layout.deviceByEntity[$0.entityID] == device }
    }

    /// Findings over the last complete day, ignored ones left out.
    func findings(now: Date = .now) async -> [Finding] {
        guard let tariff = isDemoHome ? DemoHome.tariff : EnergyTariff.load(), tariff.offPeak != nil else { return [] }
        let currency = serverConfig?.currency ?? Locale.current.currency?.identifier ?? "EUR"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }
        let meters = await electricityMeters().ids
        var found: [Finding] = []
        for sensor in devices where sensor.deviceClass == "energy" && !meters.contains(sensor.entityID)
            && ["total_increasing", "total"].contains(sensor.attributes["state_class"]?.stringValue ?? "") {
            var usage: [Int: Double] = [:]
            for point in await statistics(of: sensor.entityID, since: yesterday, period: "hour") where point.start < today {
                usage[calendar.component(.hour, from: point.start), default: 0] += max(0, point.change ?? 0)
            }
            let name = powerSwitch(for: sensor)?.name ?? sensor.name
            if let finding = PeakHoursFinding.compute(deviceID: sensor.entityID, deviceName: name, usage: usage, tariff: tariff,
                                                      currency: currency, switchEntity: powerSwitch(for: sensor)?.entityID),
                !FindingFeedback.isIgnored(finding.id) {
                found.append(finding)
            }
        }
        return found.sorted { $0.yearlyValue > $1.yearlyValue }
    }
}
