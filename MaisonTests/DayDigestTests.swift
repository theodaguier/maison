import Foundation
@testable import Maison
import Testing

@MainActor
struct DayFactsTests {
    /// Before 1:00 the demo meter's last full hour is yesterday's, and today has nothing to tell yet.
    @Test(.enabled(if: Calendar.current.component(.hour, from: .now) >= 1))
    func demoHomeHasEnergyFact() async {
        let facts = await DemoHome.store().dayFacts()
        let energy = facts.first { $0.kind == .energy }
        #expect(energy != nil)
        #expect(energy?.detail.isEmpty == false)
    }

    @Test func promptLineKeepsTitleAndDetail() {
        let fact = DayFact(kind: .energy, title: "4,2 kWh consommés", detail: "13 % de moins")
        #expect(fact.promptLine == "- 4,2 kWh consommés (13 % de moins)")
    }
}

@MainActor
struct DayDigestFallbackTests {
    /// Without the on-device model, the day keeps its facts in their written form instead of disappearing.
    @Test func withoutTheModelTheFactsStay() async {
        let digest = DayDigest(writes: false)
        let facts = [DayFact(kind: .energy, title: "4,2 kWh consommés")]
        await digest.write(facts: facts, now: [])
        #expect(digest.state == .factsOnly)
        #expect(digest.facts == facts)
        #expect(digest.written == nil)
        #expect(digest.hasContent)
    }

    @Test func aDayWithoutFactsHasNothingToOpen() async {
        let digest = DayDigest(writes: false)
        await digest.write(facts: [], now: [])
        #expect(!digest.hasContent)
    }
}
