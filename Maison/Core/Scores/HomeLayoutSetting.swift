import Foundation

/// A block of the home screen, under the three rings.
enum HomeSection: String, CaseIterable, Codable, Sendable, Identifiable {
    case summary, shortcuts, comfort, energy, network, weather, monthCost

    var id: String { rawValue }

    /// The score the section belongs to, if any.
    var score: Finding.ScoreKindID? {
        switch self {
        case .comfort, .weather: .comfort
        case .energy, .monthCost: .energy
        case .network: .network
        case .summary, .shortcuts: nil
        }
    }
}

/// What the home screen shows, in which order. Kept on the iPhone: each person arranges their own.
struct HomeLayoutSetting: Equatable, Sendable, Codable {
    var shown: [HomeSection]

    static let standard = HomeLayoutSetting(shown: [.summary, .shortcuts, .comfort, .energy, .network])
    static let key = "homeLayout"

    var hidden: [HomeSection] { HomeSection.allCases.filter { !shown.contains($0) } }

    static func load(from defaults: UserDefaults = .standard) -> HomeLayoutSetting {
        guard let data = defaults.data(forKey: key), var setting = try? JSONDecoder().decode(HomeLayoutSetting.self, from: data) else { return .standard }
        // A section saved twice, by an older build, shows once.
        var seen = Set<HomeSection>()
        setting.shown = setting.shown.filter { seen.insert($0).inserted }
        return setting
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// The order on screen: a score's section with something to fix moves ahead of the other score
    /// sections, keeping the person's order among them, and goes back to its place once it's fixed.
    func arranged(withFindings scores: Set<Finding.ScoreKindID>) -> [HomeSection] {
        let slots = shown.indices.filter { shown[$0].score != nil }
        let scored = slots.map { shown[$0] }
        let ordered = scored.filter { scores.contains($0.score!) } + scored.filter { !scores.contains($0.score!) }
        var result = shown
        for (slot, section) in zip(slots, ordered) { result[slot] = section }
        return result
    }
}

// MARK: - What the sections draw

enum HomeVisuals {
    /// The last day in `count` equal slices: up, down for at least part of it, or not known.
    enum Slice: Equatable, Sendable { case up, down, unknown }

    static func availability(outages: [DateInterval], known: DateInterval?, window: DateInterval, count: Int = 48) -> [Slice] {
        let length = window.duration / Double(count)
        return (0..<count).map { index in
            let slice = DateInterval(start: window.start.addingTimeInterval(Double(index) * length), duration: length)
            // Touching at an edge doesn't count: only a shared stretch of time does.
            func overlaps(_ interval: DateInterval) -> Bool { (interval.intersection(with: slice)?.duration ?? 0) > 0 }
            if outages.contains(where: overlaps) { return .down }
            guard let known, overlaps(known) else { return .unknown }
            return .up
        }
    }

    /// Where a value sits on a scale that holds the range and every value, from 0 to 1, with room on each side.
    static func scale(range: ClosedRange<Double>, values: [Double], margin: Double = 2) -> ClosedRange<Double> {
        let low = min(range.lowerBound, values.min() ?? range.lowerBound) - margin
        let high = max(range.upperBound, values.max() ?? range.upperBound) + margin
        return low...high
    }

    static func position(of value: Double, on scale: ClosedRange<Double>) -> Double {
        guard scale.upperBound > scale.lowerBound else { return 0.5 }
        return min(1, max(0, (value - scale.lowerBound) / (scale.upperBound - scale.lowerBound)))
    }
}
