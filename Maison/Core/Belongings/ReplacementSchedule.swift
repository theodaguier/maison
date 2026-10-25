import Foundation

/// When a consumable will need replacing, from its own history once there is one.
struct ReplacementSchedule: Sendable, Hashable {
    enum Basis: Sendable, Hashable {
        /// The category's usual lifetime, before the household has replaced it twice.
        case typical
        /// The median gap between the household's own replacements.
        case history(replacements: Int)
    }

    var intervalDays: Int
    var basis: Basis
    /// The last replacement plus the interval, pushed back when the household postponed the reminder.
    var next: Date?
    /// When the reminder shows, a few days before `next`.
    var remindOn: Date?

    /// Every value here is an estimate and is shown as one.
    var origin: ValueOrigin { .estimated }

    static let reminderLeadDays = 3

    /// - Parameters:
    ///   - events: the item's replacements, in any order; several on the same day count once.
    ///   - postponedUntil: the date the household moved the last reminder to, if they did.
    static func make(
        category: ConsumableCategory?, events: [ReplacementEvent], postponedUntil: Date? = nil,
        calendar: Calendar = .current
    ) -> ReplacementSchedule? {
        let days = Set(events.map { calendar.startOfDay(for: $0.date) }).sorted()
        let interval: Int
        let basis: Basis
        if days.count >= 2 {
            let gaps = zip(days, days.dropFirst()).compactMap { calendar.dateComponents([.day], from: $0, to: $1).day }
            interval = median(gaps)
            basis = .history(replacements: days.count)
        } else if let category {
            interval = category.typicalIntervalDays
            basis = .typical
        } else {
            return nil
        }
        var next = days.last.flatMap { calendar.date(byAdding: .day, value: interval, to: $0) }
        if let postponedUntil, let current = next, postponedUntil > current {
            next = postponedUntil
        }
        let remindOn = next.flatMap { calendar.date(byAdding: .day, value: -reminderLeadDays, to: $0) }
        return ReplacementSchedule(intervalDays: interval, basis: basis, next: next, remindOn: remindOn)
    }

    /// The middle gap, so one forgotten replacement or a double purchase doesn't skew it.
    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
