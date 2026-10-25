import CoreGraphics
import Foundation
import FoundationModels
import OSLog
import PDFKit
import Vision

/// What the on-device model reads on a document, in any language. Nothing here is kept as it is:
/// `verified(against:)` keeps only the values the document's own text backs up.
@Generable
struct ReadDocument: Equatable, Sendable {
    @Guide(description: "What the document is.")
    var type: Kind

    @Guide(description: "The shop, company or person who issued the document, written as on it. Empty if it doesn't say.")
    var merchant: String

    @Guide(description: "The date the document was issued, as YYYY-MM-DD. Empty if there is none.")
    var date: String

    @Guide(description: "The total paid or due, digits only with a dot for decimals, such as 1299.00. Empty if there is none.")
    var total: String

    @Guide(description: "The total before tax, same format. Empty if the document doesn't show it.")
    var subtotal: String

    @Guide(description: "The tax amount, same format. Empty if the document doesn't show it.")
    var tax: String

    @Guide(description: "The ISO 4217 currency code, such as EUR, USD or GBP. Empty if unknown.")
    var currency: String

    @Guide(description: "The main thing the document is about, as a short common name in the document's language, such as “Rasoir électrique” or “Lave-linge”. Empty for a contract or a bill with no product.")
    var product: String

    @Guide(description: "The product's brand, written as on the document. Empty if not written.")
    var brand: String

    @Guide(description: "The product's model or reference, written as on the document. Empty if not written.")
    var model: String

    @Guide(description: "The warranty length in months when the document states it, otherwise 0.")
    var warrantyMonths: Int

    @Guide(description: "The room the product most likely goes in, such as kitchen or bathroom, in the document's language. Empty if unclear.")
    var room: String

    @Guide(description: "One emoji that pictures the product, such as 🪒 for a razor. Empty if there is no product.")
    var emoji: String

    @Guide(description: "Whether the product is kept for years or bought again and again.")
    var kind: ProductKind

    @Guide(description: "The kind of consumable, when the product is one Maison tracks; otherwise none.")
    var consumable: Consumable

    @Generable
    enum Kind: Sendable {
        case invoice, receipt, contract, warranty, manual, quote, lease, insurance, other
    }

    @Generable
    enum ProductKind: Sendable {
        case durable, consumable
    }

    @Generable
    enum Consumable: Sendable {
        case none, razorBlades, airConditionerFilter, ventilationFilter, waterFilter, vacuumBags, lightBulb,
             laundryDetergent, dishwasherTablets, smokeDetectorBattery
    }
}

/// A document's reading once the code has checked it.
struct DocumentReading: Sendable, Hashable {
    /// The values the document's text backs up.
    var extraction: DocumentExtraction
    var emoji: String?
    var kind: ItemKind
    var category: ConsumableCategory?
    /// Values the model gave but the code didn't keep: the sheet asks for them instead.
    var rejected: Set<DocumentField>
}

enum DocumentField: Sendable, Hashable, CaseIterable {
    case merchant, date, amount, currency, brand, model, warranty
}

extension ReadDocument {
    /// Keeps a value only when the document's text shows it: the amount among the text's amounts, the brand,
    /// the model and the shop written in it, the date's year in it and the date itself plausible, the total
    /// equal to the subtotal plus tax when the document shows both.
    func verified(against text: String, now: Date = .now, calendar: Calendar = .current) -> DocumentReading {
        var rejected = Set<DocumentField>()
        var extraction = DocumentExtraction(type: type.documentType)
        let folded = DocumentText.fold(text)
        let amounts = DocumentText.amounts(in: text)

        func written(_ value: String, as field: DocumentField) -> String? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            guard folded.contains(DocumentText.fold(value)) else {
                rejected.insert(field)
                return nil
            }
            return value
        }

        extraction.merchant = written(merchant, as: .merchant)
        extraction.brand = written(brand, as: .brand)
        extraction.model = written(model, as: .model)

        if !date.isEmpty {
            if let parsed = DocumentText.isoDate(date, calendar: calendar),
               DocumentText.isPlausible(parsed, now: now, calendar: calendar),
               DocumentText.showsYear(of: parsed, in: text, calendar: calendar) {
                extraction.date = parsed
            } else {
                rejected.insert(.date)
            }
        }

        if let total = DocumentText.decimal(total) {
            let shown = amounts.contains(total)
            var adds = true
            if let subtotal = DocumentText.decimal(subtotal), let tax = DocumentText.decimal(tax),
               amounts.contains(subtotal), amounts.contains(tax) {
                adds = abs(NSDecimalNumber(decimal: subtotal + tax - total).doubleValue) <= 0.02
            }
            if shown, adds, total > 0 {
                extraction.amount = total
            } else {
                rejected.insert(.amount)
            }
        }

        let code = currency.trimmingCharacters(in: .whitespaces).uppercased()
        if !code.isEmpty {
            if Locale.Currency.isoCurrencies.contains(Locale.Currency(code)) {
                extraction.currency = code
            } else {
                rejected.insert(.currency)
            }
        }

        if warrantyMonths != 0 {
            // Written in months ("24 mois") or in years ("2 ans").
            let numbers = DocumentText.numbers(in: text)
            let stated = numbers.contains(warrantyMonths) || (warrantyMonths.isMultiple(of: 12) && numbers.contains(warrantyMonths / 12))
            if (1...120).contains(warrantyMonths), stated {
                extraction.warrantyMonths = warrantyMonths
            } else {
                rejected.insert(.warranty)
            }
        }

        let product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        extraction.product = product.isEmpty ? nil : product
        extraction.roomHint = room.isEmpty ? nil : room

        let itemKind: ItemKind = kind == .consumable ? .consumable : .durable
        return DocumentReading(
            extraction: extraction,
            emoji: DocumentText.singleEmoji(emoji),
            kind: itemKind,
            category: consumable.category,
            rejected: rejected
        )
    }
}

extension ReadDocument.Kind {
    var documentType: DocumentType {
        switch self {
        case .invoice: .invoice
        case .receipt: .receipt
        case .contract: .contract
        case .warranty: .warranty
        case .manual: .manual
        case .quote: .quote
        case .lease: .lease
        case .insurance: .insurance
        case .other: .other
        }
    }
}

extension ReadDocument.Consumable {
    var category: ConsumableCategory? {
        switch self {
        case .none: nil
        case .razorBlades: .razorBlades
        case .airConditionerFilter: .airConditionerFilter
        case .ventilationFilter: .ventilationFilter
        case .waterFilter: .waterFilter
        case .vacuumBags: .vacuumBags
        case .lightBulb: .lightBulb
        case .laundryDetergent: .laundryDetergent
        case .dishwasherTablets: .dishwasherTablets
        case .smokeDetectorBattery: .smokeDetectorBattery
        }
    }
}

/// Reads a scanned or imported document on the iPhone: text recognition, then the on-device model, then
/// the code's checks. Nothing leaves the device.
enum DocumentReader {
    private static let logger = Logger(subsystem: "com.theodaguier.maison", category: "DocumentReader")

    /// The model's context is small: the start of a document is where its type, shop, date and total are.
    static let maxCharacters = 3500

    /// The document's text, from its pages as images or from a PDF's own text when it has some.
    static func text(of pages: [CGImage]) async throws -> String {
        var lines: [String] = []
        for page in pages {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            let observations = try await request.perform(on: page)
            lines += observations.compactMap { $0.topCandidates(1).first?.string }
        }
        return lines.joined(separator: "\n")
    }

    static func text(ofPDF url: URL) async throws -> String {
        guard let pdf = PDFDocument(url: url) else { return "" }
        if let string = pdf.string, string.count > 40 { return string }
        // A scan saved as PDF has no text: render its pages and recognize them.
        let pages = (0..<min(pdf.pageCount, 3)).compactMap { pdf.page(at: $0)?.cgImage(scale: 2) }
        return try await text(of: pages)
    }

    /// Reads with Apple Intelligence when it's available; otherwise only the date, found by the system's
    /// date detection, and the household fills in the rest.
    static func read(_ text: String) async -> DocumentReading {
        guard Intelligence.isAvailable else { return readWithoutModel(text) }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Document text:\n" + String(text.prefix(maxCharacters)),
                generating: ReadDocument.self,
                options: GenerationOptions(temperature: 0)
            )
            return response.content.verified(against: text)
        } catch {
            logger.error("Document reading failed: \(String(describing: error), privacy: .public)")
            return readWithoutModel(text)
        }
    }

    static func readWithoutModel(_ text: String, now: Date = .now, calendar: Calendar = .current) -> DocumentReading {
        var extraction = DocumentExtraction()
        extraction.date = DocumentText.detectedDates(in: text)
            .filter { DocumentText.isPlausible($0, now: now, calendar: calendar) }
            .max()
        return DocumentReading(extraction: extraction, emoji: nil, kind: .durable, category: nil, rejected: [])
    }

    private static let instructions = """
    You read a document a household scanned: a bill, a receipt, a contract, a warranty, a manual or any other paper.
    The text comes from text recognition and may have errors or be in any language.
    Copy names, brands, models and amounts exactly as they are written. Never invent a value: leave it empty when the text doesn't show it.
    """
}

private extension PDFPage {
    func cgImage(scale: CGFloat) -> CGImage? {
        let bounds = bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}

/// The checks the code runs on a document's text, in every language and number format.
enum DocumentText {
    /// Lowercased, without accents, with every run of spaces as one.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "1299.00" or "79.99", as the model writes amounts.
    static func decimal(_ text: String) -> Decimal? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Every amount written in the text, whatever the format: 79,99 or 79.99, 1 299,00, 1.299,00 or 1,299.00.
    static func amounts(in text: String) -> Set<Decimal> {
        let pattern = /\d{1,3}(?:[ .,\u{00A0}\u{202F}']\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?/
        var found = Set<Decimal>()
        for match in text.matches(of: pattern) {
            let raw = String(match.output)
            if let value = parseAmount(raw) { found.insert(value) }
        }
        return found
    }

    private static func parseAmount(_ raw: String) -> Decimal? {
        var digits = raw
        // The last . or , followed by one or two digits is the decimal separator; every other separator groups thousands.
        var fraction = ""
        if let last = raw.lastIndex(where: { $0 == "." || $0 == "," }) {
            let tail = raw[raw.index(after: last)...]
            if (1...2).contains(tail.count) {
                fraction = String(tail)
                digits = String(raw[..<last])
            }
        }
        digits.removeAll { !$0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Decimal(string: fraction.isEmpty ? digits : digits + "." + fraction, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func numbers(in text: String) -> Set<Int> {
        Set(text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) })
    }

    static func isoDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    /// Not before 1990, not after tomorrow: a document can't be issued in the future.
    static func isPlausible(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let earliest = calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)),
              let latest = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        return date >= earliest && date <= latest
    }

    /// The year written in full or in two digits, as in 02/03/26.
    static func showsYear(of date: Date, in text: String, calendar: Calendar) -> Bool {
        let year = calendar.component(.year, from: date)
        let numbers = numbers(in: text)
        return numbers.contains(year) || text.contains(String(format: "%02d", year % 100))
    }

    static func detectedDates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.date)
    }

    /// One emoji, or nothing.
    static func singleEmoji(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text.count == 1, let scalar = text.unicodeScalars.first,
              scalar.properties.isEmojiPresentation || text.unicodeScalars.count > 1 && scalar.properties.isEmoji
        else { return nil }
        return text
    }
}
