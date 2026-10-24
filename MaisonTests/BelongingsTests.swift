import Foundation
import Testing
@testable import Maison

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d))!
}

struct ItemMatcherTests {
    let razor = Item(name: "Rasoir électrique", emoji: "🪒", brand: Sourced(value: "Philips", origin: .entered))
    let sofa = Item(name: "Canapé du salon", emoji: "🛋️", roomID: "salon")
    let fridge = Item(name: "Frigo", emoji: "🧊", brand: Sourced(value: "Bosch", origin: .entered))

    @Test func recognisesTheItemABillIsAbout() {
        let bill = DocumentExtraction(type: .invoice, product: "Rasoir electrique Series 5000", brand: "PHILIPS")
        #expect(ItemMatcher.match(bill, among: [razor, sofa, fridge]) == .one(razor))
    }

    @Test func offersAShortListWhenItemsAreAsLikely() {
        let shaver = Item(name: "Rasoir de voyage", brand: Sourced(value: "Philips", origin: .entered))
        let bill = DocumentExtraction(product: "Rasoir", brand: "Philips")
        guard case .several(let candidates) = ItemMatcher.match(bill, among: [razor, shaver, sofa]) else {
            Issue.record("expected several candidates")
            return
        }
        #expect(Set(candidates.map(\.id)) == [razor.id, shaver.id])
    }

    @Test func proposesNothingWhenNoItemMatches() {
        let bill = DocumentExtraction(product: "Aspirateur balai", brand: "Dyson")
        #expect(ItemMatcher.match(bill, among: [razor, sofa, fridge]) == .none)
    }
}

struct ItemPrefillTests {
    @Test func fillsEmptyFieldsFromTheDocument() {
        let razor = Item(name: "Rasoir")
        let bill = DocumentExtraction(type: .invoice, date: day(2026, 3, 2), amount: 79.99, currency: "EUR", warrantyMonths: 24)
        let result = ItemPrefill.apply(bill, to: razor, calendar: calendar)

        #expect(result.item.purchasePrice == Sourced(value: 79.99, origin: .entered))
        #expect(result.item.purchaseDate?.value == day(2026, 3, 2))
        #expect(result.item.warrantyEnd?.value == day(2028, 3, 2))
        #expect(result.item.currency == "EUR")
        #expect(result.filled == [.purchasePrice, .purchaseDate, .warrantyEnd])
        #expect(result.conflicts.isEmpty)
    }

    @Test func neverOverwritesWhatIsAlreadySet() {
        let razor = Item(name: "Rasoir", purchasePrice: Sourced(value: 89, origin: .entered))
        let bill = DocumentExtraction(amount: 79.99)
        let result = ItemPrefill.apply(bill, to: razor, calendar: calendar)

        #expect(result.item.purchasePrice?.value == 89)
        #expect(result.filled.isEmpty)
        #expect(result.conflicts.map(\.field) == [.purchasePrice])
    }

    @Test func sameValueIsNeitherFilledNorAConflict() {
        let razor = Item(name: "Rasoir", purchaseDate: Sourced(value: day(2026, 3, 2), origin: .entered))
        let result = ItemPrefill.apply(DocumentExtraction(date: day(2026, 3, 2)), to: razor, calendar: calendar)
        #expect(result.filled.isEmpty)
        #expect(result.conflicts.isEmpty)
    }
}

struct ReplacementScheduleTests {
    let blades = UUID()

    private func replaced(_ dates: Date...) -> [ReplacementEvent] {
        dates.map { ReplacementEvent(itemID: blades, date: $0, source: .manual) }
    }

    @Test func usesTheTypicalIntervalBeforeTwoReplacements() {
        let schedule = ReplacementSchedule.make(category: .razorBlades, events: replaced(day(2026, 10, 1)), calendar: calendar)
        #expect(schedule?.basis == .typical)
        #expect(schedule?.intervalDays == 42)
        #expect(schedule?.next == day(2026, 11, 12))
        #expect(schedule?.origin == .estimated)
    }

    @Test func usesTheMedianGapAfterThreeReplacements() {
        let schedule = ReplacementSchedule.make(
            category: .razorBlades,
            events: replaced(day(2026, 6, 1), day(2026, 7, 13), day(2026, 8, 26), day(2026, 10, 7)),
            calendar: calendar
        )
        // Gaps of 42, 44 and 42 days.
        #expect(schedule?.basis == .history(replacements: 4))
        #expect(schedule?.intervalDays == 42)
        #expect(schedule?.next == day(2026, 11, 18))
        #expect(schedule?.remindOn == day(2026, 11, 15))
    }

    @Test func aForgottenReplacementDoesNotSkewTheInterval() {
        let schedule = ReplacementSchedule.make(
            category: .razorBlades,
            events: replaced(day(2026, 1, 1), day(2026, 2, 12), day(2026, 3, 26), day(2026, 6, 18)),
            calendar: calendar
        )
        // Gaps of 42, 42 and 84 days: the long one is a forgotten tap, the median stays at 42.
        #expect(schedule?.intervalDays == 42)
    }

    @Test func aDoublePurchaseOnTheSameDayCountsOnce() {
        let schedule = ReplacementSchedule.make(
            category: nil, events: replaced(day(2026, 9, 1), day(2026, 9, 1), day(2026, 10, 1)), calendar: calendar
        )
        #expect(schedule?.basis == .history(replacements: 2))
        #expect(schedule?.intervalDays == 30)
    }

    @Test func aPostponedReminderMovesTheNextDate() {
        let schedule = ReplacementSchedule.make(
            category: .razorBlades, events: replaced(day(2026, 10, 1)), postponedUntil: day(2026, 11, 20), calendar: calendar
        )
        #expect(schedule?.next == day(2026, 11, 20))
    }

    @Test func noCategoryAndNoHistoryMeansNoSchedule() {
        #expect(ReplacementSchedule.make(category: nil, events: [], calendar: calendar) == nil)
    }
}

struct BelongingsDatabaseTests {
    @Test func keepsAnItemWithTheOriginOfEachValue() throws {
        let database = try BelongingsDatabase.inMemory()
        let razor = Item(
            name: "Rasoir", emoji: "🪒", roomID: "salle-de-bain",
            purchasePrice: Sourced(value: Decimal(string: "79.99")!, origin: .entered), currency: "EUR",
            purchaseDate: Sourced(value: day(2026, 3, 2), origin: .entered),
            brand: Sourced(value: "Philips", origin: .estimated)
        )
        try database.save(razor)

        let saved = try #require(try database.items().first)
        #expect(saved == razor)
        #expect(try database.items(inRoom: "salle-de-bain").count == 1)
    }

    @Test func attachesConsumablesDocumentsAndReplacements() throws {
        let database = try BelongingsDatabase.inMemory()
        let razor = Item(name: "Rasoir", emoji: "🪒")
        let blades = Item(name: "Lames", kind: .consumable, category: .razorBlades, parentItemID: razor.id)
        try database.save(razor)
        try database.save(blades)
        try database.save(HomeDocument(
            id: UUID(), itemID: razor.id, type: .invoice, merchant: "Boulanger", date: day(2026, 3, 2),
            amount: Decimal(string: "79.99"), currency: "EUR", fileRef: "doc-1.pdf",
            extraction: DocumentExtraction(type: .invoice, merchant: "Boulanger", product: "Rasoir")
        ))
        try database.save(ReplacementEvent(itemID: blades.id, date: day(2026, 9, 1), source: .document))
        try database.save(ReplacementEvent(itemID: blades.id, date: day(2026, 10, 13), source: .manual))

        #expect(try database.consumables(of: razor).map(\.id) == [blades.id])
        #expect(try database.documents(of: razor.id).first?.extraction.product == "Rasoir")
        let schedule = ReplacementSchedule.make(category: blades.category, events: try database.replacements(of: blades.id), calendar: calendar)
        #expect(schedule?.intervalDays == 42)
    }
}

struct DocumentReadingTests {
    let now = day(2026, 10, 21)

    let invoice = """
    BOULANGER
    Facture n° F-2026-0412 du 02/03/2026
    Rasoir électrique PHILIPS S5466/17
    Total HT 66,66 €
    TVA 20 % 13,33 €
    Total TTC 79,99 €
    Garantie 2 ans
    """

    func read(
        total: String = "79.99", subtotal: String = "66.66", tax: String = "13.33", date: String = "2026-03-02",
        brand: String = "PHILIPS", model: String = "S5466/17", merchant: String = "Boulanger", warranty: Int = 24,
        emoji: String = "🪒"
    ) -> ReadDocument {
        ReadDocument(
            type: .invoice, merchant: merchant, date: date, total: total, subtotal: subtotal, tax: tax, currency: "eur",
            product: "Rasoir électrique", brand: brand, model: model, warrantyMonths: warranty, room: "salle de bain",
            emoji: emoji, kind: .durable, consumable: .none
        )
    }

    @Test func keepsWhatTheTextShows() {
        let reading = read().verified(against: invoice, now: now, calendar: calendar)
        #expect(reading.rejected.isEmpty)
        #expect(reading.extraction.type == .invoice)
        #expect(reading.extraction.amount == Decimal(string: "79.99"))
        #expect(reading.extraction.currency == "EUR")
        #expect(reading.extraction.date == day(2026, 3, 2))
        #expect(reading.extraction.brand == "PHILIPS")
        #expect(reading.extraction.warrantyMonths == 24)
        #expect(reading.emoji == "🪒")
    }

    @Test func dropsAnAmountTheTextDoesNotShow() {
        let reading = read(total: "89.99").verified(against: invoice, now: now, calendar: calendar)
        #expect(reading.extraction.amount == nil)
        #expect(reading.rejected == [.amount])
    }

    @Test func dropsATotalThatDoesNotAddUp() {
        let text = invoice.replacingOccurrences(of: "TVA 20 % 13,33 €", with: "TVA 20 % 15,00 €")
        let reading = read(tax: "15.00").verified(against: text, now: now, calendar: calendar)
        #expect(reading.rejected.contains(.amount))
    }

    @Test func dropsAnInventedBrandAndAFutureDate() {
        let reading = read(date: "2027-03-02", brand: "Braun").verified(against: invoice, now: now, calendar: calendar)
        #expect(reading.extraction.brand == nil)
        #expect(reading.extraction.date == nil)
        #expect(reading.rejected == [.brand, .date])
    }

    @Test func readsAmountsInEveryFormat() {
        let amounts = DocumentText.amounts(in: "1 299,00 € | $1,299.00 | 1.299,00 | 79.99 | 12")
        #expect(amounts.contains(Decimal(string: "1299")!))
        #expect(amounts.contains(Decimal(string: "79.99")!))
        #expect(amounts.contains(12))
    }

    @Test func keepsOnlyOneEmoji() {
        #expect(DocumentText.singleEmoji("🛋️") == "🛋️")
        #expect(DocumentText.singleEmoji("🪒🪒") == nil)
        #expect(DocumentText.singleEmoji("a") == nil)
    }

    @Test func withoutTheModelFindsTheDate() {
        let reading = DocumentReader.readWithoutModel("Invoice dated March 2, 2026, total 79.99", now: now, calendar: calendar)
        #expect(reading.extraction.date.map { calendar.isDate($0, inSameDayAs: day(2026, 3, 2)) } == true)
    }
}
