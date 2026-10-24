import Foundation
import Observation
import OSLog
import PDFKit
import UIKit

/// The household's objects, documents and replacements, as the screens read them.
@MainActor
@Observable
final class BelongingsStore {
    private(set) var items: [Item] = []
    private(set) var documents: [HomeDocument] = []
    private(set) var replacements: [ReplacementEvent] = []
    /// Shown on the sheet that failed to save, never silently dropped.
    var lastError: String?

    private let database: BelongingsDatabase?
    private let filesFolder: URL?
    private static let logger = Logger(subsystem: "com.theodaguier.maison", category: "Belongings")

    init(database: BelongingsDatabase?, filesFolder: URL?) {
        self.database = database
        self.filesFolder = filesFolder
        reload()
    }

    /// The app's own database and document folder, in Application Support.
    static func onDevice() -> BelongingsStore {
        let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Documents", directoryHint: .isDirectory)
        if let folder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        do {
            return BelongingsStore(database: try .onDisk(), filesFolder: folder)
        } catch {
            logger.error("Belongings database unavailable: \(String(describing: error), privacy: .public)")
            return BelongingsStore(database: nil, filesFolder: folder)
        }
    }

    func reload() {
        guard let database else { return }
        do {
            items = try database.items()
            documents = try database.documents()
            replacements = try items.filter { $0.kind == .consumable }.flatMap { try database.replacements(of: $0.id) }
        } catch {
            report(error)
        }
    }

    // MARK: Reading

    func item(_ id: UUID?) -> Item? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// Durables first, each followed by nothing: consumables show on their durable's sheet.
    func items(in roomID: String) -> [Item] {
        items.filter { $0.roomID == roomID && $0.parentItemID == nil }
    }

    func consumables(of item: Item) -> [Item] {
        items.filter { $0.parentItemID == item.id }
    }

    func documents(of item: Item) -> [HomeDocument] {
        documents.filter { $0.itemID == item.id }
    }

    func replacements(of item: Item) -> [ReplacementEvent] {
        replacements.filter { $0.itemID == item.id }.sorted { $0.date > $1.date }
    }

    func schedule(of item: Item) -> ReplacementSchedule? {
        guard item.kind == .consumable else { return nil }
        return ReplacementSchedule.make(category: item.category, events: replacements(of: item))
    }

    func fileURL(of document: HomeDocument) -> URL? {
        filesFolder?.appending(path: document.fileRef)
    }

    // MARK: Writing

    func save(_ item: Item) {
        write { try $0.save(item) }
    }

    func delete(_ item: Item) {
        write { try $0.delete(item) }
    }

    func markReplaced(_ item: Item, on date: Date = .now, source: ReplacementEvent.Source = .manual) {
        write { try $0.save(ReplacementEvent(itemID: item.id, date: date, source: source)) }
    }

    /// Keeps a scanned document, attached to an item or not. A document about a consumable also counts as a replacement.
    @discardableResult
    func keep(_ reading: DocumentReading, pages: [UIImage], for item: Item?) -> HomeDocument? {
        guard let fileRef = storePDF(pages) else {
            lastError = String(localized: "The document couldn’t be saved on this iPhone.")
            return nil
        }
        let extraction = reading.extraction
        let document = HomeDocument(
            id: UUID(), itemID: item?.id, type: extraction.type, merchant: extraction.merchant, date: extraction.date,
            amount: extraction.amount, currency: extraction.currency, fileRef: fileRef, extraction: extraction
        )
        write { database in
            try database.save(document)
            if let item, item.kind == .consumable, [.invoice, .receipt].contains(extraction.type) {
                try database.save(ReplacementEvent(itemID: item.id, date: extraction.date ?? .now, source: .document))
            }
        }
        return document
    }

    func attach(_ document: HomeDocument, to item: Item?) {
        var document = document
        document.itemID = item?.id
        write { try $0.save(document) }
    }

    private func storePDF(_ pages: [UIImage]) -> String? {
        guard let filesFolder else { return nil }
        let pdf = PDFDocument()
        for (index, image) in pages.enumerated() {
            if let page = PDFPage(image: image) { pdf.insert(page, at: index) }
        }
        let name = UUID().uuidString + ".pdf"
        return pdf.write(to: filesFolder.appending(path: name)) ? name : nil
    }

    private func write(_ change: (BelongingsDatabase) throws -> Void) {
        guard let database else {
            lastError = String(localized: "Objects can’t be saved on this iPhone right now.")
            return
        }
        do {
            try change(database)
            lastError = nil
            reload()
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        Self.logger.error("Belongings: \(String(describing: error), privacy: .public)")
        lastError = String(localized: "Objects can’t be saved on this iPhone right now.")
    }
}

// MARK: - Demo

extension BelongingsStore {
    /// The objects of the demo home, in a throwaway database.
    static func demo() -> BelongingsStore {
        let store = BelongingsStore(database: try? .inMemory(), filesFolder: FileManager.default.temporaryDirectory)
        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: .now) ?? .now }

        let razor = Item(
            name: String(localized: "demo.item.razor", defaultValue: "Electric Razor"), emoji: "🪒", roomID: "bathroom",
            purchasePrice: Sourced(value: 79.99, origin: .entered), currency: "EUR",
            purchaseDate: Sourced(value: daysAgo(230), origin: .entered),
            warrantyEnd: Sourced(value: calendar.date(byAdding: .month, value: 24, to: daysAgo(230)) ?? .now, origin: .entered),
            brand: Sourced(value: "Philips", origin: .entered), model: Sourced(value: "S5466/17", origin: .entered)
        )
        let blades = Item(
            name: String(localized: "demo.item.blades", defaultValue: "Razor Heads"), emoji: "🪒", kind: .consumable, category: .razorBlades,
            roomID: "bathroom", parentItemID: razor.id
        )
        let airConditioner = Item(
            name: String(localized: "demo.item.ac", defaultValue: "Air Conditioner"), emoji: "❄️", roomID: "bedroom",
            linkedDeviceID: "climate.bedroom", brand: Sourced(value: "Daikin", origin: .entered)
        )
        let filter = Item(
            name: String(localized: "demo.item.filter", defaultValue: "Air Filter"), emoji: "🌬️", kind: .consumable,
            category: .airConditionerFilter, roomID: "bedroom", parentItemID: airConditioner.id
        )
        let sofa = Item(name: String(localized: "demo.item.sofa", defaultValue: "Sofa"), emoji: "🛋️", roomID: "living_room",
                        purchasePrice: Sourced(value: 1290, origin: .entered), currency: "EUR")
        for item in [razor, blades, airConditioner, filter, sofa] { store.save(item) }
        for days in [130, 88, 44] { store.markReplaced(blades, on: daysAgo(days)) }
        store.markReplaced(filter, on: daysAgo(80))
        return store
    }
}
