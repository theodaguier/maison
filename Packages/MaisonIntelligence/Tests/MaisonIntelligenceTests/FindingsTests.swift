import Foundation
@testable import MaisonIntelligence
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

    @Test func offPeakHoursMakeTheNightCheaper() throws {
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
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
        #expect(finding.kind == .peakHours)
        #expect(finding.score == .energy)
        #expect(finding.deviceID == "sensor.chauffe_eau_energy")
        #expect(finding.deviceName == "Chauffe-eau")
        #expect(finding.switchEntityID == "switch.chauffe_eau")
        #expect(finding.offPeak == offPeak)
        #expect(finding.usage == [19: 1.2, 20: 0.4])
        #expect(abs(finding.yearlyValue - 1.6 * (0.27 - 0.2068) * 365) < 0.001)
        #expect(finding.yearlyValueOrigin == .estimated)
        #expect(finding.reasons.map(\.origin) == [.measured, .entered, .estimated])
        #expect(finding.reasons[0] == .busiestHour(hour: 19, peakShare: 1))
        #expect(finding.reasons[1] == .offPeakHours(startHour: 22, endHour: 6))
        guard case .extraCost(let perDay, let currency, let peak) = finding.reasons[2] else {
            Issue.record("The third reason is the extra cost")
            return
        }
        #expect(abs(perDay - 1.6 * (0.27 - 0.2068)) < 0.0001)
        #expect(currency == "EUR")
        #expect(abs(peak - 1.6) < 0.0001)
    }

    @Test func thePeakShareCountsOnlyThePeakHours() throws {
        let finding = try #require(PeakHoursFinding.compute(
            deviceID: "d", deviceName: "Lave-linge", usage: [18: 0.9, 23: 0.1],
            tariff: EnergyTariff(price: 0.27, offPeak: offPeak), currency: "EUR", switchEntity: nil
        ))
        guard case .busiestHour(let hour, let share) = finding.reasons[0] else {
            Issue.record("The first reason is the busiest hour")
            return
        }
        #expect(hour == 18)
        #expect(abs(share - 0.9) < 0.0001)
    }

    @Test func withoutASwitchTheFindingStaysButHasNothingToSwitch() throws {
        let finding = try #require(PeakHoursFinding.compute(
            deviceID: "d", deviceName: "Lave-linge", usage: [18: 1.0],
            tariff: EnergyTariff(price: 0.27, offPeak: offPeak), currency: "EUR", switchEntity: nil
        ))
        #expect(finding.switchEntityID == nil)
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

    @Test func aFindingComesBeforeComfortOnTheHomeScreen() throws {
        let finding = try #require(PeakHoursFinding.compute(
            deviceID: "d", deviceName: "Chauffe-eau", usage: [19: 1.6],
            tariff: EnergyTariff(price: 0.27, offPeak: offPeak), currency: "EUR", switchEntity: nil
        ))
        let highlights = Highlights.compute(scores: HomeScores(hasElectricityMeter: true, findings: [finding], computedAt: .now),
                                            inputs: HighlightInputs(meterProposalSeen: true), now: .now)
        #expect(highlights.first?.id == finding.id)
        #expect(highlights.first?.score == .energy)
        #expect(highlights.first?.origin == .estimated)
        #expect(highlights.first?.fact == .finding(finding))
    }
}
