import Foundation

/// Compares words the way people write them in any language: without case, accents or curly apostrophes.
public enum WordMatching {
    /// Folded for comparison: no case, no accents, curly apostrophes made straight.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
    }

    /// Where `words` are in `text`, not inside a longer word.
    public static func wholeWordRange(of words: String, in text: String) -> Range<String.Index>? {
        guard !words.isEmpty else { return nil }
        var start = text.startIndex
        while let range = text.range(of: words, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return range }
            start = text.index(after: range.lowerBound)
        }
        return nil
    }
}
