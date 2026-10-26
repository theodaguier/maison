import Foundation

/// Checks that generated text only uses numbers found in its source, written in digits or in words.
public enum GroundedNumbers {
    public static func check(_ text: String, against source: String, locale: Locale = .current) -> Bool {
        numbers(in: text, locale: locale).isSubset(of: numbers(in: source, locale: locale))
    }

    /// Every number in the text: digit runs ("4,2" gives 4 and 2) and spelled-out words ("trois", "quatre-vingt-douze").
    public static func numbers(in text: String, locale: Locale) -> Set<Int> {
        var found = Set<Int>()
        let words = spelledOut(locale: locale)
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
            let digits = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            found.formUnion(digits)
            if digits.isEmpty, let value = words[String(token).trimmingCharacters(in: CharacterSet(charactersIn: "-"))] {
                found.insert(value)
            }
        }
        return found
    }

    private static func spelledOut(locale: Locale) -> [String: Int] {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        var words: [String: Int] = [:]
        // Up to a thousand covers the kWh, degrees and durations a home summary mentions.
        for value in 0...1000 {
            guard let word = formatter.string(from: value as NSNumber)?.lowercased() else { continue }
            words[word.replacingOccurrences(of: " ", with: "-")] = value
        }
        // "Un" and "une" are articles far more often than numbers.
        words["un"] = nil
        words["une"] = nil
        words["one"] = nil
        return words
    }
}
