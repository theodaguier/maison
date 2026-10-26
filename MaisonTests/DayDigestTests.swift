import Foundation
@testable import Maison
import Testing

@MainActor
struct DayFactsTests {
    /// Before 1:00 the demo meter's last full hour is yesterday's, and today has nothing to tell yet.
    @Test(.enabled(if: Calendar.current.component(.hour, from: .now) >= 1))
    func demoHomeHasEnergyFact() async {
        let facts = await DemoHome.store().dayFacts()
        let energy = facts.first { $0.id == "energy" }
        #expect(energy != nil)
        #expect(energy?.detail.isEmpty == false)
    }

    @Test func promptLineKeepsTitleAndDetail() {
        let fact = DayFact.energyUse(amount: 4.2, unit: "kWh", versusYesterday: .less(13))
        #expect(fact.promptLine == "- \(fact.title) (\(fact.detail))")
        #expect(fact.title.contains("kWh"))
        #expect(fact.detail.contains("13"))
    }

    /// The wording keeps every number the fact carries, so the summary can be checked against the prompt.
    @Test func wordingKeepsTheNumbers() {
        let hour = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now)!
        let peak = DayFact.temperaturePeak(entityID: "sensor.salon", room: "Salon", degrees: 23.4, hour: hour, versusYesterday: .more(1.2))
        #expect(GroundedNumbers.numbers(in: peak.promptLine, locale: .current).isSuperset(of: [23, 4, 1, 2]))

        let run = DayFact.climateRun(entityID: "climate.chambre", name: "Climatiseur", room: "Chambre", duration: 2 * 3600 + 40 * 60, target: 21, heating: false)
        #expect(GroundedNumbers.numbers(in: run.promptLine, locale: .current).isSuperset(of: [2, 40, 21]))

        let rule = DayFact.automationRuns(name: "Couloir la nuit", count: 3)
        #expect(rule.detail.isEmpty)
        #expect(rule.promptLine == "- \(rule.title)")
    }

    @Test func lockSaysWhoChangedIt() {
        let at = Date.now
        #expect(DayFact.lock(entityID: "lock.porte", name: "Porte", locked: true, at: at, by: nil).detail.isEmpty)
        #expect(DayFact.lock(entityID: "lock.porte", name: "Porte", locked: true, at: at, by: .automation("Dernier départ")).detail.contains("Dernier départ"))
        #expect(DayFact.lock(entityID: "lock.porte", name: "Porte", locked: false, at: at, by: .person("Théo")).detail.contains("Théo"))
    }

    @Test func unchangedDayReadsAsSame() {
        let same = DayFact.energyUse(amount: 4, unit: "kWh", versusYesterday: .same)
        let more = DayFact.energyUse(amount: 4, unit: "kWh", versusYesterday: .more(10))
        #expect(!same.detail.isEmpty)
        #expect(same.detail != more.detail)
        #expect(DayFact.energyUse(amount: 4, unit: "kWh", versusYesterday: nil).detail.isEmpty)
    }
}

@MainActor
struct DayDigestFallbackTests {
    /// Without the on-device model, the day keeps its facts in their written form instead of disappearing.
    @Test func withoutTheModelTheFactsStay() async {
        let digest = DayDigest(writes: false)
        let facts = [DayFact.energyUse(amount: 4.2, unit: "kWh", versusYesterday: nil)]
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
