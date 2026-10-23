import Foundation
@testable import Maison
import Testing

@MainActor
struct PlusActionTests {
    @Test func theDemoHomeOffersEveryActionThatWorksThere() {
        let store = DemoHome.store()
        let available = PlusAction.allCases.filter { $0.isAvailable(in: store) }
        // Describing a rule needs Apple Intelligence, which the test simulator may not have.
        #expect(Set(available).isSuperset(of: [.newRule, .scene, .turnOff, .testInternet, .search]))
    }

    @Test func actionsWithNothingToActOnAreHidden() {
        let store = DemoHome.store()
        let lit = store.devicesToTurnOff
        #expect(!lit.isEmpty)
        #expect(PlusAction.turnOff.isAvailable(in: store))
        // Without an internet check, testing the internet would lead nowhere.
        #expect(PlusAction.testInternet.isAvailable(in: store) == (store.internetSources != nil))
    }

    @Test func everyActionHasASymbol() {
        for action in PlusAction.allCases {
            #expect(!action.symbol.isEmpty)
        }
    }
}
