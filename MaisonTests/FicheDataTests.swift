import Foundation
@testable import Maison
import Testing

/// The fiches' data is tested in the intelligence layer. Here: the price the person entered.
struct FicheDataTests {
    @Test func anEnteredPriceIsKeptAndCanBeCleared() throws {
        let defaults = try #require(UserDefaults(suiteName: "Price-\(UUID().uuidString)"))
        #expect(EnergyPriceSetting.price(in: defaults) == nil)
        EnergyPriceSetting.set(0.2516, in: defaults)
        #expect(EnergyPriceSetting.price(in: defaults) == 0.2516)
        EnergyPriceSetting.set(0, in: defaults)
        #expect(EnergyPriceSetting.price(in: defaults) == nil)
    }
}
