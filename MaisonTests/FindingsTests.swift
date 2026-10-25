import Foundation
@testable import Maison
import Testing

struct FindingsTests {
    private let offPeak = EnergyTariff.OffPeak(price: 0.2068, startHour: 22, endHour: 6)

    // MARK: Tariff

    @Test func offPeakHoursCanCrossMidnight() {
        #expect(offPeak.contains(hour: 22))
        #expect(offPeak.contains(hour: 3))
        #expect(!offPeak.contains(hour: 6))
        #expect(!offPeak.contains(hour: 19))
        #expect(offPeak.duration == 8)
        let daytime = EnergyTariff.OffPeak(price: 0.2, startHour: 12, endHour: 14)
        #expect(daytime.contains(hour: 13) && !daytime.contains(hour: 14))
        #expect(daytime.duration == 2)
    }

    @Test func theTariffPricesEachHour() {
        let tariff = EnergyTariff(price: 0.27, offPeak: offPeak)
        #expect(tariff.price(atHour: 19) == 0.27)
        #expect(tariff.price(atHour: 23) == 0.2068)
        #expect(EnergyTariff(price: 0.25).price(atHour: 23) == 0.25)
    }

    @Test func aPriceEnteredBeforeTariffsBecomesABaseTariff() throws {
        let defaults = try #require(UserDefaults(suiteName: "Tariff-\(UUID().uuidString)"))
        #expect(EnergyTariff.load(from: defaults) == nil)
        EnergyPriceSetting.set(0.25, in: defaults)
        #expect(EnergyTariff.load(from: defaults) == EnergyTariff(price: 0.25))
        let tariff = EnergyTariff(price: 0.27, offPeak: offPeak)
        tariff.save(to: defaults)
        #expect(EnergyTariff.load(from: defaults) == tariff)
    }

    @Test func offPeakHoursMakeTheNightCheaper() {
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.startOfDay(for: day)
        let hourly = (0..<24).map { (start: midnight.addingTimeInterval(Double($0) * 3600), value: 1.0) }
        let tariff = EnergyTariff(price: 0.3, offPeak: EnergyTariff.OffPeak(price: 0.1, startHour: 22, endHour: 6))
        let cost = EnergyCost.compute(hourly: hourly, price: tariff.price(atHour:), day: midnight, asOf: midnight.addingTimeInterval(86_400), calendar: calendar)
        // 8 off-peak hours at 0.1, 16 peak hours at 0.3.
        #expect(abs(cost.day - 5.6) < 0.0001)
    }

    // MARK: Peak hours

    @Test func aWaterHeaterAtSevenPmIsWorthMovingToOffPeakHours() throws {
        let finding = try #require(PeakHoursFinding.compute(
            deviceID: "sensor.chauffe_eau_energy", deviceName: "Chauffe-eau",
            usage: [19: 1.2, 20: 0.4], tariff: EnergyTariff(price: 0.27, offPeak: offPeak),
            currency: "EUR", switchEntity: "switch.chauffe_eau"
        ))

        #expect(finding.id == "peak-hours:sensor.chauffe_eau_energy")
        #expect(abs(finding.yearlyValue - 1.6 * (0.27 - 0.2068) * 365) < 0.001)
        #expect(finding.reasons.map(\.origin) == [.measured, .entered, .estimated])
        let rule = try #require(finding.rule)
        #expect(rule.triggers == [.time(at: "22:00:00")])
        #expect(rule.actions == [
            .device(entityID: "switch.chauffe_eau", service: "switch.turn_on", data: [:]),
            .wait(minutes: 480),
            .device(entityID: "switch.chauffe_eau", service: "switch.turn_off", data: [:]),
        ])
    }

    @Test func withoutASwitchTheFindingStaysButOffersNoRule() throws {
        let finding = try #require(PeakHoursFinding.compute(
            deviceID: "d", deviceName: "Lave-linge", usage: [18: 1.0],
            tariff: EnergyTariff(price: 0.27, offPeak: offPeak), currency: "EUR", switchEntity: nil
        ))
        #expect(finding.rule == nil)
    }

    @Test func nothingToSayWithoutOffPeakHoursOrWhenAlreadyAtNight() {
        let usage = [19: 1.2, 20: 0.4]
        #expect(PeakHoursFinding.compute(deviceID: "d", deviceName: "x", usage: usage, tariff: EnergyTariff(price: 0.27),
                                         currency: "EUR", switchEntity: nil) == nil)
        #expect(PeakHoursFinding.compute(deviceID: "d", deviceName: "x", usage: [23: 1.0, 2: 1.0], tariff: EnergyTariff(price: 0.27, offPeak: offPeak),
                                         currency: "EUR", switchEntity: nil) == nil)
        #expect(PeakHoursFinding.compute(deviceID: "d", deviceName: "x", usage: [19: 0.2], tariff: EnergyTariff(price: 0.27, offPeak: offPeak),
                                         currency: "EUR", switchEntity: nil) == nil)
    }

    @Test func anIgnoredFindingStaysIgnored() throws {
        let defaults = try #require(UserDefaults(suiteName: "Findings-\(UUID().uuidString)"))
        #expect(!FindingFeedback.isIgnored("peak-hours:d", in: defaults))
        FindingFeedback.ignore("peak-hours:d", in: defaults)
        FindingFeedback.ignore("peak-hours:d", in: defaults)
        #expect(FindingFeedback.isIgnored("peak-hours:d", in: defaults))
        #expect(defaults.stringArray(forKey: FindingFeedback.ignoredKey)?.count == 1)
    }

    @Test func aFindingComesBeforeComfortOnTheHomeScreen() throws {
        let finding = try #require(PeakHoursFinding.compute(
            deviceID: "d", deviceName: "Chauffe-eau", usage: [19: 1.6],
            tariff: EnergyTariff(price: 0.27, offPeak: offPeak), currency: "EUR", switchEntity: nil
        ))
        let highlights = Highlights.compute(scores: HomeScores(hasElectricityMeter: true, findings: [finding], computedAt: .now),
                                            inputs: HighlightInputs(meterProposalSeen: true))
        #expect(highlights.first?.id == finding.id)
        #expect(highlights.first?.score == .energy)
    }
}
