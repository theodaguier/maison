import Foundation
@testable import Maison
import Testing

struct FicheDataTests {
    private func weather(_ temperature: Double, _ condition: String = "sunny") -> OutdoorWeather {
        OutdoorWeather(temperature: temperature, humidity: 60, condition: condition)
    }

    // MARK: Airing

    @Test func risingCarbonDioxideAsksToAirWhenOutsideAllows() {
        let advice = AiringAdvice.compute(outdoor: weather(8), carbonDioxide: [("Salon", 1140), ("Chambre", 700)])
        #expect(advice?.reason == .carbonDioxide(room: "Salon", ppm: 1140))
    }

    @Test func aMildDryDayIsAGoodMomentEvenWithoutSensors() {
        #expect(AiringAdvice.compute(outdoor: weather(18), carbonDioxide: [])?.reason == .mildOutside)
        // Too cold to air for pleasure, fine to air for CO₂.
        #expect(AiringAdvice.compute(outdoor: weather(8), carbonDioxide: []) == nil)
    }

    @Test func rainFrostOrHeatNeverAskToOpenTheWindows() {
        #expect(AiringAdvice.compute(outdoor: weather(18, "rainy"), carbonDioxide: [("Salon", 1500)]) == nil)
        #expect(AiringAdvice.compute(outdoor: weather(2), carbonDioxide: [("Salon", 1500)]) == nil)
        #expect(AiringAdvice.compute(outdoor: weather(31), carbonDioxide: [("Salon", 1500)]) == nil)
        #expect(AiringAdvice.compute(outdoor: nil, carbonDioxide: [("Salon", 1500)]) == nil)
    }

    // MARK: Cost

    @Test func costIsTheDayTimesThePriceAndTheMonthAtTheSamePace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        // The 10th of the month at noon: nine full days, then half a day.
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let asOf = day.addingTimeInterval(12 * 3600)
        let monthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let hourly = stride(from: monthStart.timeIntervalSince1970, to: asOf.timeIntervalSince1970, by: 3600).map {
            (start: Date(timeIntervalSince1970: $0), value: 0.5)
        }

        let cost = EnergyCost.compute(hourly: hourly, price: 0.25, day: day, asOf: asOf, calendar: calendar)

        #expect(abs(cost.day - 1.5) < 0.0001) // 12 hours × 0.5 kWh × 0.25
        // June, no clock change: 9.5 days used (114 kWh), then 20.5 days at 12 kWh, × 0.25.
        let month = try #require(cost.monthProjection)
        #expect(abs(month - 90) < 0.01)
    }

    @Test func noMonthProjectionWithoutAHabit() {
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let hourly = (0..<6).map { (start: day.addingTimeInterval(Double($0) * 3600), value: 1.0) }
        let cost = EnergyCost.compute(hourly: hourly, price: 0.2, day: day, asOf: day.addingTimeInterval(6 * 3600))
        #expect(abs(cost.day - 1.2) < 0.0001)
        #expect(cost.monthProjection == nil)
    }

    @Test func anEnteredPriceIsKeptAndCanBeCleared() throws {
        let defaults = try #require(UserDefaults(suiteName: "Price-\(UUID().uuidString)"))
        #expect(EnergyPriceSetting.price(in: defaults) == nil)
        EnergyPriceSetting.set(0.2516, in: defaults)
        #expect(EnergyPriceSetting.price(in: defaults) == 0.2516)
        EnergyPriceSetting.set(0, in: defaults)
        #expect(EnergyPriceSetting.price(in: defaults) == nil)
    }

    // MARK: Comfort room

    @Test func theRoomCardShowsTheTemperatureInTheMiddleOfTheExcursion() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let series = TimeSeries(changes: [
            StateChange(state: "21", date: start),
            StateChange(state: "24.5", date: start.addingTimeInterval(3600)),
            StateChange(state: "25", date: start.addingTimeInterval(2 * 3600)),
            StateChange(state: "21", date: start.addingTimeInterval(3 * 3600)),
        ])
        let score = try #require(ComfortScore.compute(rooms: [("bedroom", "Chambre", series)], range: 20...22, rangeOrigin: .entered,
                                                      window: DateInterval(start: start, duration: 86_400)))
        #expect(score.rooms[0].readings.count == 4)
        #expect(score.rooms[0].excursionValue == 25)
    }
}
