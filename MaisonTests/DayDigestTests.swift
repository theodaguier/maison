import Foundation
@testable import Maison
import Testing

struct GroundedNumbersTests {
    let french = Locale(identifier: "fr_FR")

    @Test func keepsNumbersCopiedFromTheFacts() {
        let facts = "- 4,2 kWh consommés (13 % de moins qu’hier)\n- La porte verrouillée à 8 h 12"
        let text = "4,2 kWh ont été consommés, soit 13 % de moins qu’hier. La porte est verrouillée depuis 8 h 12."
        #expect(GroundedNumbers.check(text, against: facts, locale: french))
    }

    @Test func rejectsARewrittenNumber() {
        let facts = "- 4,2 kWh consommés"
        #expect(!GroundedNumbers.check("92 kWh ont été consommés.", against: facts, locale: french))
        #expect(!GroundedNumbers.check("Quatre-vingt-douze kilowattheures ont été consommées.", against: facts, locale: french))
    }

    @Test func acceptsSpelledOutNumbersFromTheFacts() {
        let facts = "- “Couloir la nuit” 3 fois\n- Trois lumières sont allumées"
        #expect(GroundedNumbers.check("Le couloir s’est allumé trois fois, et trois lumières sont allumées.", against: facts, locale: french))
    }

    @Test func ignoresArticles() {
        #expect(GroundedNumbers.check("Une journée calme, avec un pic au salon.", against: "- Pic au salon", locale: french))
    }
}

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
