import Foundation

// How a finding reads on screen. The intelligence layer gives the values; the words and their
// translations stay here, on the iPhone.

extension Finding {
    var title: String {
        switch kind {
        case .peakHours: String(localized: "\(deviceName): mostly in peak hours")
        }
    }
}

extension Finding.Reason {
    var symbol: String {
        switch self {
        case .busiestHour: "clock.fill"
        case .offPeakHours: "doc.text.fill"
        case .extraCost: "number"
        }
    }

    var title: String {
        switch self {
        case .busiestHour(let hour, _):
            String(localized: "Most of it around \(hour):00")
        case .offPeakHours(let startHour, let endHour):
            String(localized: "Off-peak from \(startHour):00 to \(endHour):00")
        case .extraCost(let perDay, let currency, _):
            String(localized: "\(perDay.formatted(.number.precision(.fractionLength(2)))) \(currency.currencySymbol) more per day")
        }
    }

    var detail: String {
        switch self {
        case .busiestHour(_, let peakShare):
            String(localized: "\(Int((peakShare * 100).rounded())) % of its use in peak hours")
        case .offPeakHours:
            String(localized: "your tariff")
        case .extraCost(_, _, let peakKilowattHours):
            String(localized: "\(peakKilowattHours.formatted(.number.precision(.fractionLength(1)))) kWh at the peak price")
        }
    }
}
