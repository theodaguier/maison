import Foundation
import FoundationModels
import Observation
import OSLog

/// The day summary as the on-device model writes it.
@Generable
struct WrittenDay: Equatable, Sendable {
    @Guide(description: "Two short sentences for a card on the home screen: what stood out today, then how the home is right now.")
    var brief: String

    @Guide(description: "Two short paragraphs telling how the day went, in the order things happened, separated by a blank line. Doesn't repeat the brief word for word.")
    var story: String
}

/// Writes the day summary with Apple's on-device model, from facts computed beforehand.
/// Nothing leaves the iPhone. When the model isn't available, or the person turned the summary off,
/// the day keeps its facts in their written form instead of disappearing.
@MainActor
@Observable
final class DayDigest {
    enum State: Equatable {
        case idle
        case writing
        case written(WrittenDay)
        /// Only the facts, in their written form: the model isn't used on this iPhone.
        case factsOnly
        case failed
    }

    /// Whether the on-device model words the day, or only its facts are kept.
    let writes: Bool
    private(set) var state: State = .idle
    private(set) var facts: [DayFact] = []
    private(set) var writtenAt: Date?

    init(writes: Bool = DayDigest.isAvailable) {
        self.writes = writes
    }

    /// Whether this iPhone can write the summary: Apple Intelligence on, model downloaded, language supported.
    static var isAvailable: Bool { Intelligence.isAvailable }

    private static let logger = Logger(subsystem: "com.theodaguier.maison", category: "DayDigest")

    var written: WrittenDay? {
        if case .written(let day) = state { day } else { nil }
    }

    /// Whether there is something to read: a written summary, or at least the day's facts.
    var hasContent: Bool { written != nil || (state == .factsOnly && !facts.isEmpty) }

    /// Writes the summary unless a recent one is still fresh.
    func refreshIfNeeded(from store: HomeStore, now current: [String]) async {
        if let writtenAt, hasContent, Date.now.timeIntervalSince(writtenAt) < 30 * 60 { return }
        await write(from: store, now: current)
    }

    /// `current` describes the home right now, as the summary card's plain sentences do.
    func write(from store: HomeStore, now current: [String]) async {
        guard state != .writing else { return }
        state = .writing
        await write(facts: store.dayFacts(), now: current)
    }

    /// Words the facts, or keeps them as they are when the model isn't used.
    func write(facts: [DayFact], now current: [String]) async {
        state = .writing
        self.facts = facts
        guard writes, Self.isAvailable else {
            state = .factsOnly
            writtenAt = .now
            return
        }
        #if DEBUG
        // `-writtenDay` shows a summary the model wrote on a Mac for the demo home: the simulator's model
        // can't generate (its content safety assets are missing), and the design still needs checking.
        if UserDefaults.standard.bool(forKey: "writtenDay") {
            state = .written(WrittenDay(
                brief: "La température a atteint 23,4° au salon aujourd’hui. La porte d’entrée est verrouillée depuis 8 h 12.",
                story: "Le climatiseur a fonctionné pendant 2 h 40 min dans la chambre. La porte d’entrée a été verrouillée à 8 h 12 par « Dernier départ ».\n\n4,2 kWh ont été consommés, soit 13 % de moins qu’hier à la même heure. Trois lumières sont allumées au salon, et Sonos joue « Clair de lune »."
            ))
            writtenAt = .now
            return
        }
        #endif
        let prompt = Self.prompt(facts: facts, current: current)
        // The model sometimes rewrites a number ("92 kWh" for 4,2): a summary is only kept
        // when every number in it comes from the facts.
        for _ in 0..<2 {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let response = try await session.respond(
                    to: prompt,
                    generating: WrittenDay.self,
                    options: GenerationOptions(temperature: 0.3)
                )
                let day = response.content
                guard GroundedNumbers.check(day.brief + "\n" + day.story, against: prompt) else {
                    Self.logger.info("Day summary rejected: a number isn't in the facts")
                    continue
                }
                state = .written(day)
                writtenAt = .now
                return
            } catch {
                Self.logger.error("Day summary failed: \(String(describing: error), privacy: .public)")
                break
            }
        }
        state = .failed
    }

    // MARK: Prompt

    private static var instructions: String {
        let language = Intelligence.languageName
        return """
        You write the daily summary of a home for the people who live there. It appears in their home app.
        Use only the facts you are given. Never add an event, a device, a person, a time or a number that isn't in them, \
        and copy numbers and times exactly as written, in digits. Keep names in quotes exactly as written.
        Don't describe anything as stable, usual or unusual unless a fact says so.
        Write in \(language), plainly and warmly. Address the reader formally ("vous" in French) and never guess their gender.
        No greeting, no emoji, no list, no markdown, no advice.
        """
    }

    private static func prompt(facts: [DayFact], current: [String]) -> String {
        let day = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        var lines = ["Now: \(day)."]
        if !facts.isEmpty {
            lines.append("What happened today:")
            lines += facts.map(\.promptLine)
        }
        if !current.isEmpty {
            lines.append("The home right now:")
            lines += current.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}

/// Checks that generated text only uses numbers found in its source, written in digits or in words.
enum GroundedNumbers {
    static func check(_ text: String, against source: String, locale: Locale = .current) -> Bool {
        numbers(in: text, locale: locale).isSubset(of: numbers(in: source, locale: locale))
    }

    /// Every number in the text: digit runs ("4,2" gives 4 and 2) and spelled-out words ("trois", "quatre-vingt-douze").
    static func numbers(in text: String, locale: Locale) -> Set<Int> {
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
