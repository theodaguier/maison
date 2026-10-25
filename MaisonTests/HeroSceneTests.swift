import Foundation
@testable import Maison
import Testing

struct HeroSceneTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 25 October 2026 at `hours` UTC.
    private func at(_ hours: Double, month: Int = 10) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: month, day: 25))!
        return day.addingTimeInterval(hours * 3600)
    }

    @Test func periodFollowsTheSun() {
        let sunrise = at(7.5), sunset = at(18)
        #expect(HeroScene.Period.at(at(3), sunrise: sunrise, sunset: sunset) == .night)
        #expect(HeroScene.Period.at(at(7.1), sunrise: sunrise, sunset: sunset) == .dawn)
        #expect(HeroScene.Period.at(at(8.4), sunrise: sunrise, sunset: sunset) == .dawn)
        #expect(HeroScene.Period.at(at(12), sunrise: sunrise, sunset: sunset) == .day)
        #expect(HeroScene.Period.at(at(17.5), sunrise: sunrise, sunset: sunset) == .dusk)
        #expect(HeroScene.Period.at(at(18.4), sunrise: sunrise, sunset: sunset) == .dusk)
        #expect(HeroScene.Period.at(at(19), sunrise: sunrise, sunset: sunset) == .night)
    }

    @Test func withoutTheSunTheDayRunsFromSevenToSeven() {
        #expect(HeroScene.at(at(6.75), calendar: calendar).period == .dawn)
        #expect(HeroScene.at(at(13), calendar: calendar).period == .day)
        #expect(HeroScene.at(at(18.5), calendar: calendar).period == .dusk)
        #expect(HeroScene.at(at(22), calendar: calendar).period == .night)
    }

    @Test func sunTimesFromTheNextOnes() {
        // Sun up at noon: next setting today, next rising tomorrow.
        let up = HeroScene.sunTimes(nextRising: at(31.5), nextSetting: at(18))
        #expect(up.sunrise == at(7.5))
        #expect(up.sunset == at(18))
        // Sun down at 3 am: next rising today, next setting today.
        let down = HeroScene.sunTimes(nextRising: at(7.5), nextSetting: at(18))
        #expect(down.sunrise == at(7.5))
        #expect(down.sunset == at(-6))
    }

    @Test func weatherFromTheCondition() {
        #expect(HeroScene.Weather(condition: "sunny") == .clear)
        #expect(HeroScene.Weather(condition: "partlycloudy") == .clear)
        #expect(HeroScene.Weather(condition: "clear-night") == .clear)
        #expect(HeroScene.Weather(condition: "cloudy") == .cloudy)
        #expect(HeroScene.Weather(condition: "pouring") == .rain)
        #expect(HeroScene.Weather(condition: "lightning-rainy") == .storm)
        #expect(HeroScene.Weather(condition: "snowy-rainy") == .snow)
        #expect(HeroScene.Weather(condition: "fog") == .fog)
        #expect(HeroScene.Weather(condition: nil) == .clear)
    }

    @Test func seasonsFlipSouthOfTheEquator() {
        #expect(HeroScene.Season.of(month: 10) == .autumn)
        #expect(HeroScene.Season.of(month: 1) == .winter)
        #expect(HeroScene.Season.of(month: 10, southern: true) == .spring)
        #expect(HeroScene.Season.of(month: 7, southern: true) == .winter)
    }

    @Test func candidatesGoFromClosestToBundled() {
        let scene = HeroScene(period: .dusk, weather: .rain, season: .autumn)
        #expect(scene.candidates == ["HeroDuskRainAutumn", "HeroDuskRain", "HeroDayRain", "HeroDuskClear", "HeroDayClear"])
        let night = HeroScene(period: .night, weather: .clear, season: .winter)
        #expect(night.candidates == ["HeroNightClearWinter", "HeroNightClear"])
    }

    @Test func everySceneEndsOnABundledPainting() {
        for period in HeroScene.Period.allCases {
            for weather in HeroScene.Weather.allCases {
                for season in HeroScene.Season.allCases {
                    let last = HeroScene(period: period, weather: weather, season: season).candidates.last
                    #expect(last == (period == .night ? "HeroNightClear" : "HeroDayClear"))
                }
            }
        }
    }

    @Test func assetIsTheFirstTheCatalogHas() {
        let scene = HeroScene(period: .dawn, weather: .fog, season: .spring)
        #expect(scene.asset { ["HeroDawnClear", "HeroDayClear"].contains($0) } == "HeroDawnClear")
        // A foggy dawn shows the day's fog before a clear dawn.
        #expect(scene.asset { ["HeroDawnClear", "HeroDayFog", "HeroDayClear"].contains($0) } == "HeroDayFog")
        #expect(scene.asset { _ in false } == "HeroDayClear")
    }

    @Test func paintingsAreTheNumberedVariantsOfTheAsset() {
        let catalog: Set = ["HeroDayClear", "HeroDayClear2", "HeroDayClear3", "HeroDayClear5", "HeroNightClear"]
        let rain = HeroScene(period: .day, weather: .rain, season: .autumn)
        // No rain painting: the clear day's three, and the gap stops the count.
        #expect(rain.paintings(in: catalog.contains) == ["HeroDayClear", "HeroDayClear2", "HeroDayClear3"])
        let night = HeroScene(period: .night, weather: .clear, season: .autumn)
        #expect(night.paintings(in: catalog.contains) == ["HeroNightClear"])
    }

    @Test func nextPaintingIsNeverTheLastOne() {
        var generator = SystemRandomNumberGenerator()
        let paintings = ["HeroDayClear", "HeroDayClear2", "HeroDayClear3"]
        for _ in 0..<50 {
            let next = HeroScene.next(among: paintings, after: "HeroDayClear2", using: &generator)
            #expect(next != "HeroDayClear2")
            #expect(paintings.contains(next))
        }
        // A single painting comes back, and a first opening takes any.
        #expect(HeroScene.next(among: ["HeroNightClear"], after: "HeroNightClear", using: &generator) == "HeroNightClear")
        #expect(paintings.contains(HeroScene.next(among: paintings, after: nil, using: &generator)))
    }

    @Test func appearanceKeepsTheWeather() {
        let day = HeroScene(period: .day, weather: .snow, season: .winter)
        #expect(day.dark == HeroScene(period: .night, weather: .snow, season: .winter))
        #expect(day.light == day)
        let night = HeroScene(period: .night, weather: .rain, season: .autumn)
        #expect(night.light == HeroScene(period: .dusk, weather: .rain, season: .autumn))
        #expect(night.dark == night)
    }

    @MainActor @Test func storeReadsTheWeather() {
        // The demo home's weather entity is partly cloudy.
        #expect(DemoHome.store().heroScene().weather == .clear)
    }
}
