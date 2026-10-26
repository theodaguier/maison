import Foundation

// How a day fact reads in the summary sheet and in the model's prompt. The intelligence layer gives the
// values; the words and their translations stay here, on the iPhone. Numbers keep the exact formatting
// the prompt carries, since `GroundedNumbers` checks the summary against it.

extension DayFact {
    var title: String {
        switch self {
        case .temperaturePeak(_, let room, let degrees, _, _):
            let degrees = EntityState.degrees(degrees)
            return if let room {
                String(localized: "Peak of \(degrees) \(Phrasing.location(room))")
            } else {
                String(localized: "Peak of \(degrees)")
            }
        case .climateRun(_, let name, _, let duration, _, _):
            let duration = Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            return String(localized: "\(Phrasing.subject(name)) ran for \(duration)")
        case .lock(_, let name, let locked, let date, _):
            let state = Phrasing.agree(locked ? String(localized: "Locked") : String(localized: "Unlocked"), with: name)
            return String(localized: "\(Phrasing.subject(name)) \(state.lowercased()) at \(Phrasing.time(date))")
        case .energyUse(let amount, let unit, _):
            let amount = amount.formatted(.number.precision(.fractionLength(0...1)))
            return String(localized: "\(amount) \(unit) used")
        case .automationRuns(let name, let count):
            return String(localized: "“\(name)” ran \(count) times")
        }
    }

    var detail: String {
        switch self {
        case .temperaturePeak(_, _, _, let hour, let change):
            var detail = String(localized: "Around \(Phrasing.hour(hour))")
            if let change {
                let comparison = switch change {
                case .same: String(localized: "as warm as yesterday")
                case .more(let difference): String(localized: "\(Self.tenths(difference))° warmer than yesterday")
                case .less(let difference): String(localized: "\(Self.tenths(difference))° cooler than yesterday")
                }
                detail += ", " + comparison
            }
            return detail
        case .climateRun(_, _, let room, _, let target, _):
            var details: [String] = []
            if let room { details.append(room) }
            if let target { details.append(String(localized: "set to \(EntityState.degrees(target))")) }
            return details.joined(separator: ", ")
        case .lock(_, _, _, _, let actor):
            return switch actor {
            case .automation(let automation): String(localized: "By “\(automation)”")
            case .person(let person): String(localized: "By \(person)")
            case nil: ""
            }
        case .energyUse(_, _, let change):
            return switch change {
            case nil: ""
            case .same: String(localized: "Same as yesterday at this time")
            case .less(let percent): String(localized: "\(Int(percent))% less than yesterday at this time")
            case .more(let percent): String(localized: "\(Int(percent))% more than yesterday at this time")
            }
        case .automationRuns:
            return ""
        }
    }

    /// The fact as one line of the model's prompt.
    var promptLine: String { detail.isEmpty ? "- \(title)" : "- \(title) (\(detail))" }

    private static func tenths(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
