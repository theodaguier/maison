import Foundation

/// How a home's electricity meter can be read, from the country it is in. Data, not code: a country is a
/// line in `ports`. Whatever the way, the reader joins the Wi-Fi, Home Assistant finds it, and Maison adds it.
enum MeterReading: Equatable, Sendable {
    /// A reader plugged into the smart meter's local port.
    case port(SmartMeterPort)
    /// A clamp on the main cable in the electrical panel, which works with any meter, in any country.
    case clamp

    enum SmartMeterPort: String, Sendable {
        /// France: the Linky's customer information port.
        case tic
        /// Netherlands, Belgium, Luxembourg.
        case p1
        /// The Nordic countries, Austria, Switzerland.
        case han

        var name: String {
            switch self {
            case .tic: "TIC"
            case .p1: "P1"
            case .han: "HAN"
            }
        }
    }

    /// Countries whose smart meters have a local port a Wi-Fi reader can use, by ISO 3166 code.
    static let ports: [String: SmartMeterPort] = [
        "FR": .tic,
        "NL": .p1, "BE": .p1, "LU": .p1,
        "SE": .han, "NO": .han, "FI": .han, "DK": .han, "AT": .han, "CH": .han,
    ]

    /// `country` as Home Assistant has it, otherwise the iPhone's region.
    static func forCountry(_ country: String?, region: String? = Locale.current.region?.identifier) -> MeterReading {
        guard let code = (country ?? region)?.uppercased(), let port = ports[code] else { return .clamp }
        return .port(port)
    }
}
