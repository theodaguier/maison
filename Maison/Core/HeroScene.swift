import Foundation

/// The painting behind the home screen: a landscape at the moment of the day, in the weather and the season
/// outside. Each combination has its own paintings in the bank, one of them shown at each opening; a missing
/// one falls back to a close one, down to the clear day and the clear night, which are always there.
struct HeroScene: Sendable, Hashable {
    enum Period: String, Sendable, CaseIterable {
        case dawn, day, dusk, night

        /// Dawn and dusk are short: from half an hour before the sun crosses the horizon to an hour on
        /// the lit side.
        static func at(_ date: Date, sunrise: Date, sunset: Date) -> Period {
            if date >= sunrise.addingTimeInterval(-1800), date < sunrise.addingTimeInterval(3600) { return .dawn }
            if date >= sunset.addingTimeInterval(-3600), date < sunset.addingTimeInterval(1800) { return .dusk }
            return date > sunrise && date < sunset ? .day : .night
        }
    }

    enum Weather: String, Sendable, CaseIterable {
        case clear, cloudy, rain, storm, snow, fog

        /// From Home Assistant's condition; a light sky with a few clouds stays clear, as in the paintings.
        init(condition: String?) {
            switch condition {
            case "cloudy", "windy", "windy-variant", "exceptional": self = .cloudy
            case "rainy", "pouring": self = .rain
            case "lightning", "lightning-rainy", "hail": self = .storm
            case "snowy", "snowy-rainy": self = .snow
            case "fog": self = .fog
            default: self = .clear
            }
        }
    }

    enum Season: String, Sendable, CaseIterable {
        case spring, summer, autumn, winter

        /// Meteorological seasons: whole months, flipped south of the equator.
        static func of(month: Int, southern: Bool = false) -> Season {
            let north: Season = switch month {
            case 3...5: .spring
            case 6...8: .summer
            case 9...11: .autumn
            default: .winter
            }
            guard southern else { return north }
            return switch north {
            case .spring: .autumn
            case .summer: .winter
            case .autumn: .spring
            case .winter: .summer
            }
        }
    }

    let period: Period
    let weather: Weather
    let season: Season

    /// The scene under dark text: light mode keeps a lit sky, so the night waits at dusk.
    var light: HeroScene { period == .night ? HeroScene(period: .dusk, weather: weather, season: season) : self }

    /// The scene under light text: dark mode keeps the night, whatever the clock says.
    var dark: HeroScene { HeroScene(period: .night, weather: weather, season: season) }

    /// Asset names, the closest first: the season can be missing, then dawn and dusk borrow the day's
    /// weather, which shows more than the hour, then the weather can be missing. The last one is always in
    /// the catalog.
    var candidates: [String] {
        let base = period == .night ? Period.night : .day
        var names = [Self.name(period, weather, season), Self.name(period, weather)]
        if base != period { names.append(Self.name(base, weather)) }
        names.append(Self.name(period, .clear))
        if base != period { names.append(Self.name(base, .clear)) }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// The first candidate the catalog has.
    func asset(in catalog: (String) -> Bool) -> String {
        candidates.first(where: catalog) ?? candidates.last!
    }

    /// Every painting of that candidate: "HeroDayClear", then "HeroDayClear2", "HeroDayClear3"…
    func paintings(in catalog: (String) -> Bool) -> [String] {
        let first = asset(in: catalog)
        return [first] + (2...).lazy.map { "\(first)\($0)" }.prefix(while: catalog)
    }

    /// Another painting than the last one shown, when there is another.
    static func next(
        among paintings: [String], after last: String?, using generator: inout some RandomNumberGenerator
    ) -> String {
        let others = paintings.filter { $0 != last }
        return others.randomElement(using: &generator) ?? paintings[0]
    }

    /// "HeroDuskRain", "HeroDayClearWinter".
    static func name(_ period: Period, _ weather: Weather, _ season: Season? = nil) -> String {
        "Hero" + [period.rawValue, weather.rawValue, season?.rawValue].compactMap { $0?.capitalized }.joined()
    }

    /// Without a sunrise and a sunset, the sun rises at 7 and sets at 19.
    static func at(
        _ date: Date, sunrise: Date? = nil, sunset: Date? = nil, condition: String? = nil,
        southern: Bool = false, calendar: Calendar = .current
    ) -> HeroScene {
        let day = calendar.startOfDay(for: date)
        let rise = sunrise ?? day.addingTimeInterval(7 * 3600)
        let set = sunset ?? day.addingTimeInterval(19 * 3600)
        return HeroScene(
            period: .at(date, sunrise: rise, sunset: set),
            weather: Weather(condition: condition),
            season: .of(month: calendar.component(.month, from: date), southern: southern)
        )
    }

    /// Today's sunrise and sunset from the next ones: when the sun is up, it rose about a day before it next
    /// rises; when it is down, it set about a day before it next sets.
    static func sunTimes(nextRising: Date, nextSetting: Date) -> (sunrise: Date, sunset: Date) {
        nextSetting < nextRising
            ? (nextRising.addingTimeInterval(-86_400), nextSetting)
            : (nextRising, nextSetting.addingTimeInterval(-86_400))
    }
}

extension HomeStore {
    /// The scene outside now, from the server's sun, weather and home zone when it has them.
    func heroScene(at date: Date = .now) -> HeroScene {
        let sun = states["sun.sun"].flatMap { sun -> (sunrise: Date, sunset: Date)? in
            guard let rising = sun.attributes["next_rising"]?.stringValue.flatMap(EntityState.parseDate),
                  let setting = sun.attributes["next_setting"]?.stringValue.flatMap(EntityState.parseDate) else { return nil }
            return HeroScene.sunTimes(nextRising: rising, nextSetting: setting)
        }
        let latitude = states["zone.home"]?.attributes["latitude"]?.doubleValue
        return .at(date, sunrise: sun?.sunrise, sunset: sun?.sunset, condition: outdoorWeather?.condition, southern: (latitude ?? 0) < 0)
    }
}
