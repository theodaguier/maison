import Foundation

// Electricity read from the grid operator, with the customer's consent and no hardware: the smart meter
// already reports to it. One source for Maison, one line per country in `GridOperator.byCountry`.
// The operator's client credentials can't ship in the app, so every call goes through Maison's relay,
// which holds them and stores nothing (see relay/README.md).

/// A grid operator or national data hub that hands a customer's meter readings to a service they approve.
struct GridOperator: Equatable, Sendable, Identifiable {
    /// Stable id, also the relay's path (`enedis`).
    let id: String
    /// Shown to the person: "Enedis".
    let name: String
    /// Whether Maison has a connector for it yet. The others are known, and wait for one.
    let isSupported: Bool

    /// By ISO 3166 code. Countries without a line have no such service (Germany, Sweden for now): the
    /// meter reader and the bill remain.
    static let byCountry: [String: GridOperator] = [
        "FR": GridOperator(id: "enedis", name: "Enedis", isSupported: true),
        "ES": GridOperator(id: "datadis", name: "Datadis", isSupported: false),
        "DK": GridOperator(id: "eloverblik", name: "Eloverblik", isSupported: false),
        "NO": GridOperator(id: "elhub", name: "Elhub", isSupported: false),
        "FI": GridOperator(id: "fingrid-datahub", name: "Datahub", isSupported: false),
        "EE": GridOperator(id: "estfeed", name: "Estfeed", isSupported: false),
        "NL": GridOperator(id: "edsn", name: "EDSN", isSupported: false),
        "AT": GridOperator(id: "eda", name: "EDA", isSupported: false),
        "IT": GridOperator(id: "portale-consumi", name: "Portale Consumi", isSupported: false),
        "GB": GridOperator(id: "dcc", name: "Smart Data Communications", isSupported: false),
        "AU": GridOperator(id: "cdr-energy", name: "Consumer Data Right", isSupported: false),
    ]

    /// The operator Maison can link in `country` (Home Assistant's), otherwise the iPhone's region.
    static func supported(in country: String?, region: String? = Locale.current.region?.identifier) -> GridOperator? {
        guard let code = (country ?? region)?.uppercased(), let found = byCountry[code], found.isSupported else { return nil }
        return found
    }
}

/// What the person approved: the operator, and the meter it lets Maison read.
struct GridLink: Codable, Equatable, Sendable {
    let operatorID: String
    /// Enedis's PRM, Datadis's CUPS: the operator's id for the meter.
    let meterID: String
    /// Signed by the relay for this meter alone: knowing a meter id (it is on every bill) is not enough
    /// to read its consumption.
    var accessKey: String = ""
    let linkedAt: Date
    /// The end of the last reading imported into Home Assistant.
    var importedUntil: Date?

    static let key = "gridLink"

    static func load(from defaults: UserDefaults = .standard) -> GridLink? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(GridLink.self, from: $0) }
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    static func remove(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// Maison's relay, from the build setting `MAISON_RELAY_URL`. Without it, no grid operator is offered.
enum MaisonRelay {
    static let infoDictionaryKey = "MaisonRelayURL"

    static var url: URL? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, !raw.contains("$("), let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
}

/// Enedis Data Connect, through the relay. The person approves Maison once on Enedis's site; Enedis then
/// gives the half-hour load curve of the day before, or the daily total when the curve isn't collected.
struct EnedisDataConnect: Sendable {
    let relay: URL
    var client: any HTTPClient = URLSessionHTTPClient()

    static let callbackScheme = "maison"

    /// Opens Enedis's consent page; it comes back as `maison://grid/enedis?usage_point_id=…&access=…&state=…`.
    func authorizationURL(state: String) -> URL {
        relay.appending(path: "enedis/authorize").appending(queryItems: [URLQueryItem(name: "state", value: state)])
    }

    /// The meter the person approved and the relay's key for it, once the state matches the one sent.
    /// `nil` when they refused or anything is missing.
    static func link(fromCallback url: URL, expectedState: String) -> (meterID: String, accessKey: String)? {
        guard url.scheme == callbackScheme, url.host() == "grid",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard value("state") == expectedState, value("error") == nil,
              let meter = value("usage_point_id"), let access = value("access") else { return nil }
        return (meter, access)
    }

    /// Energy used each hour between `start` and `end` (Enedis keeps three years), in kWh.
    /// Falls back to one value per day when the load curve isn't collected.
    func hourlyConsumption(meter: String, accessKey: String, from start: Date, to end: Date) async throws -> [(start: Date, value: Double)] {
        do {
            let curve = try await get("consumption_load_curve", meter: meter, accessKey: accessKey, from: start, to: end)
            return Self.hourly(fromLoadCurve: curve)
        } catch EnedisError.loadCurveNotCollected {
            let daily = try await get("daily_consumption", meter: meter, accessKey: accessKey, from: start, to: end)
            return Self.daily(from: daily)
        }
    }

    enum EnedisError: Error, Equatable {
        case loadCurveNotCollected
        case refused(statusCode: Int)
    }

    private func get(_ resource: String, meter: String, accessKey: String, from start: Date, to end: Date) async throws -> JSONValue {
        let url = relay.appending(path: "enedis/\(resource)").appending(queryItems: [
            URLQueryItem(name: "usage_point_id", value: meter),
            URLQueryItem(name: "start", value: Self.day(start)),
            URLQueryItem(name: "end", value: Self.day(end)),
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await client.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Enedis answers 404 with ADAM-ERR0123 when the household never turned the load curve on.
        if resource == "consumption_load_curve", status == 404 || status == 403 { throw EnedisError.loadCurveNotCollected }
        guard (200..<300).contains(status) else { throw EnedisError.refused(statusCode: status) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Enedis's dates are local French time, "2026-10-21 03:30:00", each stamping the end of its interval.
    private static let timeZone = TimeZone(identifier: "Europe/Paris")!

    /// "2026-10-21", the day in France.
    static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ text: String) -> Date? {
        let parts = text.split(separator: " ")
        var components = DateComponents()
        let day = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard day.count == 3 else { return nil }
        (components.year, components.month, components.day) = (day[0], day[1], day[2])
        let time = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [0, 0, 0]
        components.hour = time.first ?? 0
        components.minute = time.count > 1 ? time[1] : 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)
    }

    /// Average power (W) over each interval, summed into energy per hour.
    static func hourly(fromLoadCurve body: JSONValue) -> [(start: Date, value: Double)] {
        var byHour: [Date: Double] = [:]
        for reading in body["meter_reading"]?["interval_reading"]?.arrayValue ?? [] {
            guard let end = reading["date"]?.stringValue.flatMap(date), let watts = reading["value"]?.stringValue.flatMap(Double.init) else { continue }
            let minutes = reading["interval_length"]?.stringValue.flatMap(Self.minutes) ?? 30
            let start = end.addingTimeInterval(-Double(minutes) * 60)
            let hour = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
            byHour[hour, default: 0] += watts * Double(minutes) / 60 / 1000
        }
        return byHour.map { (start: $0.key, value: $0.value) }.sorted { $0.start < $1.start }
    }

    /// One value per day, in Wh, stamped at the day's start: kept as that day's first hour.
    static func daily(from body: JSONValue) -> [(start: Date, value: Double)] {
        (body["meter_reading"]?["interval_reading"]?.arrayValue ?? []).compactMap { reading in
            guard let day = reading["date"]?.stringValue.flatMap(date), let wattHours = reading["value"]?.stringValue.flatMap(Double.init) else { return nil }
            return (start: day, value: wattHours / 1000)
        }
        .sorted { $0.start < $1.start }
    }

    /// "PT30M" → 30.
    private static func minutes(_ duration: String) -> Int? {
        guard duration.hasPrefix("PT"), duration.hasSuffix("M") else { return nil }
        return Int(duration.dropFirst(2).dropLast())
    }
}
