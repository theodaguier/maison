import Foundation

/// Fills an item's empty fields from a document, without ever overwriting what the household already set.
enum ItemPrefill {
    enum Field: String, Sendable, Hashable {
        case purchasePrice, purchaseDate, warrantyEnd, brand, model
    }

    /// A field that already has a value and a document that says otherwise: shown for confirmation.
    struct Conflict: Sendable, Hashable {
        var field: Field
        var current: String
        var proposed: String
    }

    struct Result: Sendable, Hashable {
        var item: Item
        var filled: [Field]
        var conflicts: [Conflict]
    }

    static func apply(_ extraction: DocumentExtraction, to item: Item, calendar: Calendar = .current) -> Result {
        var item = item
        var filled: [Field] = []
        var conflicts: [Conflict] = []

        func merge<Value>(_ field: Field, _ keyPath: WritableKeyPath<Item, Sourced<Value>?>, _ proposed: Value?, describe: (Value) -> String) {
            guard let proposed else { return }
            if let current = item[keyPath: keyPath] {
                if current.value != proposed {
                    conflicts.append(Conflict(field: field, current: describe(current.value), proposed: describe(proposed)))
                }
            } else {
                item[keyPath: keyPath] = Sourced(value: proposed, origin: .entered)
                filled.append(field)
            }
        }

        let day = Date.FormatStyle(date: .numeric, time: .omitted)
        merge(.purchasePrice, \.purchasePrice, extraction.amount) { "\($0)" }
        if item.currency == nil, extraction.amount != nil { item.currency = extraction.currency }
        merge(.purchaseDate, \.purchaseDate, extraction.date) { $0.formatted(day) }
        let warrantyEnd = extraction.warrantyMonths.flatMap { months in
            (extraction.date ?? item.purchaseDate?.value).flatMap { calendar.date(byAdding: .month, value: months, to: $0) }
        }
        merge(.warrantyEnd, \.warrantyEnd, warrantyEnd) { $0.formatted(day) }
        merge(.brand, \.brand, extraction.brand) { $0 }
        merge(.model, \.model, extraction.model) { $0 }
        return Result(item: item, filled: filled, conflicts: conflicts)
    }
}
