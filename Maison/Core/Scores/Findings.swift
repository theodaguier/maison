import Foundation

// What the person did with a finding, kept on the iPhone. The findings themselves are computed in the
// intelligence layer; their wording is in `Finding+Wording.swift`, their rule in `Finding+Rule.swift`.

/// Rules Maison created from a finding, by id, with when. Kept on the iPhone that created them.
enum ProposedRules {
    static let key = "rulesFromFindings"

    static func createdAt(_ ruleID: String, in defaults: UserDefaults = .standard) -> Date? {
        (defaults.dictionary(forKey: key)?[ruleID] as? Double).map { Date(timeIntervalSince1970: $0) }
    }

    static func add(_ ruleID: String, at date: Date = .now, in defaults: UserDefaults = .standard) {
        var rules = defaults.dictionary(forKey: key) ?? [:]
        rules[ruleID] = date.timeIntervalSince1970
        defaults.set(rules, forKey: key)
    }

    static func remove(_ ruleID: String, in defaults: UserDefaults = .standard) {
        var rules = defaults.dictionary(forKey: key) ?? [:]
        rules[ruleID] = nil
        defaults.set(rules, forKey: key)
    }
}

/// Things the person said about a finding: ignored, or wrong and why. Kept on the iPhone.
enum FindingFeedback {
    static let ignoredKey = "ignoredFindings"

    static func isIgnored(_ id: String, in defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: ignoredKey) ?? []).contains(id)
    }

    static func ignore(_ id: String, in defaults: UserDefaults = .standard) {
        defaults.set(Array(Set((defaults.stringArray(forKey: ignoredKey) ?? []) + [id])), forKey: ignoredKey)
    }
}
