import Foundation

// What the person entered about their electricity, kept on the iPhone, and how a currency is written.
// The fiches' data itself (weather, airing, price, cost, devices, router) is computed in the
// intelligence layer.

/// The price entered in Maison when Home Assistant has none.
enum EnergyPriceSetting {
    static let key = "energyPricePerKilowattHour"

    static func price(in defaults: UserDefaults = .standard) -> Double? {
        (defaults.object(forKey: key) as? Double).flatMap { $0 > 0 ? $0 : nil }
    }

    static func set(_ price: Double?, in defaults: UserDefaults = .standard) {
        defaults.set(price, forKey: key)
    }
}

/// The tariff entered in Maison, kept on the iPhone.
extension EnergyTariff {
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

extension String {
    /// "EUR" → "€".
    var currencySymbol: String {
        if Locale.current.currency?.identifier == self, let symbol = Locale.current.currencySymbol { return symbol }
        return Locale(identifier: "fr_FR").currency?.identifier == self ? (Locale(identifier: "fr_FR").currencySymbol ?? self) : self
    }
}
