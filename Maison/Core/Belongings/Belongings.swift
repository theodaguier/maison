import Foundation

/// A value and its origin.
struct Sourced<Value: Sendable & Hashable>: Sendable, Hashable {
    var value: Value
    var origin: ValueOrigin
}

extension Sourced: Codable where Value: Codable {}

/// Durable things are kept for years; consumables are bought again and again.
enum ItemKind: String, Sendable, Hashable, Codable {
    case durable
    case consumable

    /// Shown until the household or Apple Intelligence picks a better one.
    var defaultEmoji: String {
        switch self {
        case .durable: "📦"
        case .consumable: "🔁"
        }
    }
}

/// Consumables Maison knows a typical lifetime for, used until the household's own history takes over.
enum ConsumableCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case razorBlades
    case airConditionerFilter
    case ventilationFilter
    case waterFilter
    case vacuumBags
    case lightBulb
    case laundryDetergent
    case dishwasherTablets
    case smokeDetectorBattery

    /// A common replacement interval, in days. Only a starting point: shown as an estimate.
    var typicalIntervalDays: Int {
        switch self {
        case .razorBlades: 42
        case .airConditionerFilter: 90
        case .ventilationFilter: 180
        case .waterFilter: 60
        case .vacuumBags: 60
        case .lightBulb: 365
        case .laundryDetergent: 42
        case .dishwasherTablets: 45
        case .smokeDetectorBattery: 365
        }
    }
}

/// Something in the home, connected or not. Only the name is required: an item can start almost empty.
struct Item: Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var emoji: String
    var kind: ItemKind
    var category: ConsumableCategory?
    var roomID: String?
    /// The durable a consumable belongs to: blades to a razor, a filter to an air conditioner.
    var parentItemID: UUID?
    /// The Home Assistant entity this item is, when it is connected.
    var linkedDeviceID: String?
    var purchasePrice: Sourced<Decimal>?
    var currency: String?
    var purchaseDate: Sourced<Date>?
    var warrantyEnd: Sourced<Date>?
    var brand: Sourced<String>?
    var model: Sourced<String>?

    init(
        id: UUID = UUID(), name: String, emoji: String? = nil, kind: ItemKind = .durable,
        category: ConsumableCategory? = nil, roomID: String? = nil, parentItemID: UUID? = nil,
        linkedDeviceID: String? = nil, purchasePrice: Sourced<Decimal>? = nil, currency: String? = nil,
        purchaseDate: Sourced<Date>? = nil, warrantyEnd: Sourced<Date>? = nil,
        brand: Sourced<String>? = nil, model: Sourced<String>? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji ?? kind.defaultEmoji
        self.kind = kind
        self.category = category
        self.roomID = roomID
        self.parentItemID = parentItemID
        self.linkedDeviceID = linkedDeviceID
        self.purchasePrice = purchasePrice
        self.currency = currency
        self.purchaseDate = purchaseDate
        self.warrantyEnd = warrantyEnd
        self.brand = brand
        self.model = model
    }
}

/// The kinds of paper a household keeps.
enum DocumentType: String, Sendable, Hashable, Codable, CaseIterable {
    case invoice, receipt, contract, warranty, manual, quote, lease, insurance, other
}

/// A scanned or imported document, attached to an item when it is about one.
struct HomeDocument: Sendable, Hashable, Identifiable {
    var id: UUID
    var itemID: UUID?
    var type: DocumentType
    var merchant: String?
    var date: Date?
    var amount: Decimal?
    var currency: String?
    /// Where the file is stored on the device.
    var fileRef: String
    var extraction: DocumentExtraction
}

/// What was read on a document. Amounts and dates come from text recognition and parsing; the product
/// and the kind of document may come from the on-device model.
struct DocumentExtraction: Sendable, Hashable, Codable {
    var type: DocumentType = .other
    var merchant: String?
    var date: Date?
    var amount: Decimal?
    var currency: String?
    var product: String?
    var brand: String?
    var model: String?
    var warrantyMonths: Int?
    var roomHint: String?
}

/// One replacement of a consumable: from a scanned invoice, or a tap on "Replaced".
struct ReplacementEvent: Sendable, Hashable, Identifiable {
    enum Source: String, Sendable, Hashable, Codable {
        case document, manual
    }

    var id: UUID = UUID()
    var itemID: UUID
    var date: Date
    var source: Source
}
