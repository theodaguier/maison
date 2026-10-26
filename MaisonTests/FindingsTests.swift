import Foundation
@testable import Maison
import Testing

/// The findings' values are tested in the intelligence layer. Here: what the person entered or did,
/// the rule a finding proposes, and the words it shows.
struct FindingsTests {
    private let offPeak = EnergyTariff.OffPeak(price: 0.2068, startHour: 22, endHour: 6)

    private func waterHeater(switchEntity: String?) throws -> Finding {
        try #require(PeakHoursFinding.compute(
            deviceID: "sensor.chauffe_eau_energy", deviceName: "Chauffe-eau",
            usage: [19: 1.2, 20: 0.4], tariff: EnergyTariff(price: 0.27, offPeak: offPeak),
            currency: "EUR", switchEntity: switchEntity
        ))
    }

    // MARK: Tariff

    @Test func aPriceEnteredBeforeTariffsBecomesABaseTariff() throws {
        let defaults = try #require(UserDefaults(suiteName: "Tariff-\(UUID().uuidString)"))
        #expect(EnergyTariff.load(from: defaults) == nil)
        EnergyPriceSetting.set(0.25, in: defaults)
        #expect(EnergyTariff.load(from: defaults) == EnergyTariff(price: 0.25))
        let tariff = EnergyTariff(price: 0.27, offPeak: offPeak)
        tariff.save(to: defaults)
        #expect(EnergyTariff.load(from: defaults) == tariff)
    }

    // MARK: Rule

    @Test func aWaterHeaterAtSevenPmIsMovedToOffPeakHoursByItsSwitch() throws {
        let rule = try #require(waterHeater(switchEntity: "switch.chauffe_eau").rule)
        #expect(rule.triggers == [.time(at: "22:00:00")])
        #expect(rule.actions == [
            .device(entityID: "switch.chauffe_eau", service: "switch.turn_on", data: [:]),
            .wait(minutes: 480),
            .device(entityID: "switch.chauffe_eau", service: "switch.turn_off", data: [:]),
        ])
        #expect(rule.name == String(localized: "\("Chauffe-eau") in off-peak hours"))
        #expect(rule.description == String(localized: "Created by Maison: runs only during the off-peak hours of your tariff."))
    }

    @Test func withoutASwitchTheFindingStaysButOffersNoRule() throws {
        #expect(try waterHeater(switchEntity: nil).rule == nil)
    }

    // MARK: Wording

    @Test func eachReasonKeepsItsSymbolAndOrigin() throws {
        let finding = try waterHeater(switchEntity: nil)
        #expect(finding.reasons.map(\.symbol) == ["clock.fill", "doc.text.fill", "number"])
        #expect(finding.reasons.map(\.origin) == [.measured, .entered, .estimated])
    }

    /// The same keys as before the values moved to the intelligence layer, so the string catalog's
    /// translations still match, in whatever language the simulator runs.
    @Test func aFindingKeepsItsLocalizedKeys() throws {
        let finding = try waterHeater(switchEntity: nil)
        let peak = 1.6
        let extraPerDay = peak * (0.27 - 0.2068)
        #expect(finding.title == String(localized: "\("Chauffe-eau"): mostly in peak hours"))
        #expect(finding.reasons.map(\.title) == [
            String(localized: "Most of it around \(19):00"),
            String(localized: "Off-peak from \(22):00 to \(6):00"),
            String(localized: "\(extraPerDay.formatted(.number.precision(.fractionLength(2)))) \("EUR".currencySymbol) more per day"),
        ])
        #expect(finding.reasons.map(\.detail) == [
            String(localized: "\(100) % of its use in peak hours"),
            String(localized: "your tariff"),
            String(localized: "\(peak.formatted(.number.precision(.fractionLength(1)))) kWh at the peak price"),
        ])
    }

    // MARK: Feedback

    @Test func anIgnoredFindingStaysIgnored() throws {
        let defaults = try #require(UserDefaults(suiteName: "Findings-\(UUID().uuidString)"))
        #expect(!FindingFeedback.isIgnored("peak-hours:d", in: defaults))
        FindingFeedback.ignore("peak-hours:d", in: defaults)
        FindingFeedback.ignore("peak-hours:d", in: defaults)
        #expect(FindingFeedback.isIgnored("peak-hours:d", in: defaults))
        #expect(defaults.stringArray(forKey: FindingFeedback.ignoredKey)?.count == 1)
    }

    @Test func aFindingHighlightReadsAsTheFinding() throws {
        let finding = try waterHeater(switchEntity: nil)
        let highlight = Highlight(id: finding.id, score: finding.score, fact: .finding(finding), origin: .estimated, rank: .worth)
        #expect(highlight.title == finding.title)
        #expect(highlight.kind == .energy)
    }
}
