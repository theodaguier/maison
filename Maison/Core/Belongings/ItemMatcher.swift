import Foundation

/// Finds which item a document is about, when it was scanned from anywhere but the item's own sheet.
enum ItemMatcher {
    enum Match: Equatable {
        /// One item stands out: Maison proposes it, the household confirms with one tap.
        case one(Item)
        /// A few items are as likely: Maison shows a short list.
        case several([Item])
        /// Nothing matches: Maison offers to create the item, prefilled from the document.
        case none
    }

    /// Below this score an item isn't proposed at all.
    static let threshold = 2.0
    /// An item stands out when it beats the next one by this much.
    static let margin = 1.5
    static let maxCandidates = 3

    static func match(_ extraction: DocumentExtraction, among items: [Item]) -> Match {
        let scored = items
            .map { ($0, score($0, extraction)) }
            .filter { $0.1 >= threshold }
            .sorted { $0.1 > $1.1 }
        guard let best = scored.first else { return .none }
        if scored.count == 1 || best.1 - scored[1].1 >= margin {
            return .one(best.0)
        }
        let close = scored.prefix { best.1 - $0.1 < margin }.prefix(maxCandidates).map(\.0)
        return .several(Array(close))
    }

    /// Brand and model weigh most, then the words shared by the item's name and the product read on the document.
    static func score(_ item: Item, _ extraction: DocumentExtraction) -> Double {
        var score = 0.0
        if let brand = extraction.brand, let itemBrand = item.brand?.value, normalized(brand) == normalized(itemBrand) {
            score += 3
        }
        if let model = extraction.model, let itemModel = item.model?.value {
            let a = normalized(model), b = normalized(itemModel)
            if !a.isEmpty, !b.isEmpty, a.contains(b) || b.contains(a) { score += 4 }
        }
        let product = Set(tokens(extraction.product ?? ""))
        let name = Set(tokens(item.name))
        if !product.isEmpty, !name.isEmpty {
            let shared = Double(product.intersection(name).count)
            score += 3 * shared / Double(name.count)
        }
        if let room = extraction.roomHint, let itemRoom = item.roomID, normalized(room) == normalized(itemRoom) {
            score += 1
        }
        return score
    }

    private static let stopWords: Set<String> = ["le", "la", "les", "de", "du", "des", "un", "une", "et", "a", "the", "of", "and"]

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }
}
