import Foundation
import GRDB

/// Objects, documents and replacements, kept in SQLite on the device.
struct BelongingsDatabase: Sendable {
    let writer: any DatabaseWriter

    /// The app's database, in Application Support.
    static func onDisk() throws -> BelongingsDatabase {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try BelongingsDatabase(writer: DatabaseQueue(path: folder.appending(path: "belongings.sqlite").path()))
    }

    /// A throwaway database, for tests and previews.
    static func inMemory() throws -> BelongingsDatabase {
        try BelongingsDatabase(writer: DatabaseQueue())
    }

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("category", .text)
                t.column("roomID", .text)
                t.column("parentItemID", .text).references("item", onDelete: .setNull)
                t.column("linkedDeviceID", .text)
                t.column("purchasePrice", .text)
                t.column("purchasePriceOrigin", .text)
                t.column("currency", .text)
                t.column("purchaseDate", .datetime)
                t.column("purchaseDateOrigin", .text)
                t.column("warrantyEnd", .datetime)
                t.column("warrantyEndOrigin", .text)
                t.column("brand", .text)
                t.column("brandOrigin", .text)
                t.column("model", .text)
                t.column("modelOrigin", .text)
            }
            try db.create(table: "document") { t in
                t.primaryKey("id", .text)
                t.column("itemID", .text).references("item", onDelete: .setNull)
                t.column("type", .text).notNull()
                t.column("merchant", .text)
                t.column("date", .datetime)
                t.column("amount", .text)
                t.column("currency", .text)
                t.column("fileRef", .text).notNull()
                t.column("extraction", .jsonText).notNull()
            }
            try db.create(table: "replacementEvent") { t in
                t.primaryKey("id", .text)
                t.column("itemID", .text).notNull().references("item", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("source", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: Items

    func save(_ item: Item) throws {
        try writer.write { try item.save($0) }
    }

    func delete(_ item: Item) throws {
        _ = try writer.write { try item.delete($0) }
    }

    func items() throws -> [Item] {
        try writer.read { try Item.order(Column("name")).fetchAll($0) }
    }

    func items(inRoom roomID: String) throws -> [Item] {
        try writer.read { try Item.filter(Column("roomID") == roomID).order(Column("name")).fetchAll($0) }
    }

    /// The consumables that belong to a durable: blades to a razor, a filter to an air conditioner.
    func consumables(of item: Item) throws -> [Item] {
        try writer.read { try Item.filter(Column("parentItemID") == item.id.uuidString).order(Column("name")).fetchAll($0) }
    }

    // MARK: Documents

    func save(_ document: HomeDocument) throws {
        try writer.write { try document.save($0) }
    }

    func documents(of itemID: UUID? = nil) throws -> [HomeDocument] {
        try writer.read { db in
            var request = HomeDocument.order(Column("date").desc)
            if let itemID { request = request.filter(Column("itemID") == itemID.uuidString) }
            return try request.fetchAll(db)
        }
    }

    // MARK: Replacements

    func save(_ event: ReplacementEvent) throws {
        try writer.write { try event.save($0) }
    }

    func replacements(of itemID: UUID) throws -> [ReplacementEvent] {
        try writer.read { try ReplacementEvent.filter(Column("itemID") == itemID.uuidString).order(Column("date")).fetchAll($0) }
    }
}

// MARK: - Records

private func sourced<Value>(_ row: Row, _ column: String) -> Sourced<Value>? where Value: DatabaseValueConvertible {
    guard let value: Value = row[column] else { return nil }
    let origin = (row[column + "Origin"] as String?).flatMap(ValueOrigin.init(rawValue:)) ?? .entered
    return Sourced(value: value, origin: origin)
}

private func decimal(_ text: String?) -> Decimal? {
    text.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
}

extension Item: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "item" }

    init(row: Row) {
        let price: String? = row["purchasePrice"]
        self.init(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            name: row["name"],
            emoji: row["emoji"],
            kind: ItemKind(rawValue: row["kind"]) ?? .durable,
            category: (row["category"] as String?).flatMap(ConsumableCategory.init(rawValue:)),
            roomID: row["roomID"],
            parentItemID: (row["parentItemID"] as String?).flatMap(UUID.init(uuidString:)),
            linkedDeviceID: row["linkedDeviceID"],
            purchasePrice: decimal(price).map {
                Sourced(value: $0, origin: (row["purchasePriceOrigin"] as String?).flatMap(ValueOrigin.init(rawValue:)) ?? .entered)
            },
            currency: row["currency"],
            purchaseDate: sourced(row, "purchaseDate"),
            warrantyEnd: sourced(row, "warrantyEnd"),
            brand: sourced(row, "brand"),
            model: sourced(row, "model")
        )
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["name"] = name
        container["emoji"] = emoji
        container["kind"] = kind.rawValue
        container["category"] = category?.rawValue
        container["roomID"] = roomID
        container["parentItemID"] = parentItemID?.uuidString
        container["linkedDeviceID"] = linkedDeviceID
        container["purchasePrice"] = purchasePrice.map { NSDecimalNumber(decimal: $0.value).stringValue }
        container["purchasePriceOrigin"] = purchasePrice?.origin.rawValue
        container["currency"] = currency
        container["purchaseDate"] = purchaseDate?.value
        container["purchaseDateOrigin"] = purchaseDate?.origin.rawValue
        container["warrantyEnd"] = warrantyEnd?.value
        container["warrantyEndOrigin"] = warrantyEnd?.origin.rawValue
        container["brand"] = brand?.value
        container["brandOrigin"] = brand?.origin.rawValue
        container["model"] = model?.value
        container["modelOrigin"] = model?.origin.rawValue
    }
}

extension HomeDocument: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "document" }

    init(row: Row) {
        let json: String = row["extraction"]
        self.init(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            itemID: (row["itemID"] as String?).flatMap(UUID.init(uuidString:)),
            type: DocumentType(rawValue: row["type"]) ?? .other,
            merchant: row["merchant"],
            date: row["date"],
            amount: decimal(row["amount"]),
            currency: row["currency"],
            fileRef: row["fileRef"],
            extraction: (try? JSONDecoder().decode(DocumentExtraction.self, from: Data(json.utf8))) ?? DocumentExtraction()
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["itemID"] = itemID?.uuidString
        container["type"] = type.rawValue
        container["merchant"] = merchant
        container["date"] = date
        container["amount"] = amount.map { NSDecimalNumber(decimal: $0).stringValue }
        container["currency"] = currency
        container["fileRef"] = fileRef
        container["extraction"] = String(decoding: try JSONEncoder().encode(extraction), as: UTF8.self)
    }
}

extension ReplacementEvent: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "replacementEvent" }

    init(row: Row) {
        self.init(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            itemID: UUID(uuidString: row["itemID"]) ?? UUID(),
            date: row["date"],
            source: Source(rawValue: row["source"]) ?? .manual
        )
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["itemID"] = itemID.uuidString
        container["date"] = date
        container["source"] = source.rawValue
    }
}
