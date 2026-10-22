import Foundation
@testable import Maison
import Testing

struct GridOperatorTests {
    private let relay = URL(string: "https://relay.maison.example")!

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func parisDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Countries

    @Test func onlyFranceHasAConnectorYet() {
        #expect(GridOperator.supported(in: "FR")?.id == "enedis")
        #expect(GridOperator.supported(in: "fr")?.name == "Enedis")
        // Known, waiting for a connector.
        #expect(GridOperator.byCountry["ES"]?.name == "Datadis")
        #expect(GridOperator.supported(in: "ES") == nil)
        // No such service.
        #expect(GridOperator.byCountry["DE"] == nil)
        #expect(GridOperator.supported(in: nil, region: "FR")?.id == "enedis")
        #expect(GridOperator.supported(in: "DE", region: "FR") == nil)
    }

    @Test func theLinkIsKeptAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "GridLink-\(UUID().uuidString)"))
        #expect(GridLink.load(from: defaults) == nil)
        var link = GridLink(operatorID: "enedis", meterID: "12345678901234", linkedAt: Date(timeIntervalSinceReferenceDate: 0))
        link.importedUntil = Date(timeIntervalSinceReferenceDate: 86_400)
        link.save(to: defaults)
        #expect(GridLink.load(from: defaults) == link)
        GridLink.remove(from: defaults)
        #expect(GridLink.load(from: defaults) == nil)
    }

    // MARK: Consent

    @Test func consentGoesThroughTheRelay() {
        let url = EnedisDataConnect(relay: relay).authorizationURL(state: "abc")
        #expect(url.absoluteString == "https://relay.maison.example/enedis/authorize?state=abc")
    }

    @Test func theCallbackGivesTheMeterOnlyWithTheRightState() throws {
        let callback = try #require(URL(string: "maison://grid/enedis?usage_point_id=09876543210987&state=abc"))
        #expect(EnedisDataConnect.meterID(fromCallback: callback, expectedState: "abc") == "09876543210987")
        #expect(EnedisDataConnect.meterID(fromCallback: callback, expectedState: "other") == nil)
        let homeAssistant = try #require(URL(string: "maison://auth-callback?code=x&state=abc"))
        #expect(EnedisDataConnect.meterID(fromCallback: homeAssistant, expectedState: "abc") == nil)
        let empty = try #require(URL(string: "maison://grid/enedis?usage_point_id=&state=abc"))
        #expect(EnedisDataConnect.meterID(fromCallback: empty, expectedState: "abc") == nil)
    }

    // MARK: Readings

    @Test func halfHourPowerBecomesHourlyEnergy() {
        // Average watts over 30 minutes, each stamped at the end of its interval, French time.
        let body: JSONValue = ["meter_reading": ["interval_reading": [
            ["value": "1000", "date": "2026-10-21 00:30:00", "interval_length": "PT30M"],
            ["value": "2000", "date": "2026-10-21 01:00:00", "interval_length": "PT30M"],
            ["value": "600", "date": "2026-10-21 01:30:00", "interval_length": "PT30M"],
        ]]]
        let hourly = EnedisDataConnect.hourly(fromLoadCurve: body)
        #expect(hourly.map(\.start) == [parisDate(2026, 10, 21, 0), parisDate(2026, 10, 21, 1)])
        #expect(hourly.map(\.value) == [1.5, 0.3])
    }

    @Test func dailyTotalsAreInWattHours() {
        let body: JSONValue = ["meter_reading": ["interval_reading": [
            ["value": "8200", "date": "2026-10-20"],
            ["value": "7400", "date": "2026-10-21"],
        ]]]
        let daily = EnedisDataConnect.daily(from: body)
        #expect(daily.map(\.start) == [parisDate(2026, 10, 20), parisDate(2026, 10, 21)])
        #expect(daily.map(\.value) == [8.2, 7.4])
    }

    @Test func daysAreAskedInFrenchTime() {
        // 23:30 in Paris on the 20th is already the 21st in UTC+0's eyes, never the reverse.
        #expect(EnedisDataConnect.day(parisDate(2026, 10, 20, 23, 30)) == "2026-10-20")
        #expect(EnedisDataConnect.day(parisDate(2026, 10, 21)) == "2026-10-21")
    }

    @Test func withoutTheLoadCurveTheDailyTotalIsAsked() async throws {
        let http = ScriptedHTTPClient { request in
            request.url?.path() == "/enedis/consumption_load_curve"
                ? (404, #"{"error": "ADAM-ERR0123"}"#)
                : (200, #"{"meter_reading": {"interval_reading": [{"value": "9100", "date": "2026-10-21"}]}}"#)
        }
        let readings = try await EnedisDataConnect(relay: relay, client: http)
            .hourlyConsumption(meter: "12345678901234", from: parisDate(2026, 10, 21), to: parisDate(2026, 10, 22))

        #expect(readings.map(\.value) == [9.1])
        #expect(http.sent.map { $0.url?.path() } == ["/enedis/consumption_load_curve", "/enedis/daily_consumption"])
        let query = URLComponents(url: http.sent[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "usage_point_id" }?.value == "12345678901234")
        #expect(query.first { $0.name == "start" }?.value == "2026-10-21")
        #expect(query.first { $0.name == "end" }?.value == "2026-10-22")
    }

    @Test func aRefusalIsNotMistakenForAMissingCurve() async throws {
        let http = ScriptedHTTPClient { _ in (500, "") }
        await #expect(throws: EnedisDataConnect.EnedisError.refused(statusCode: 500)) {
            _ = try await EnedisDataConnect(relay: relay, client: http)
                .hourlyConsumption(meter: "1", from: parisDate(2026, 10, 21), to: parisDate(2026, 10, 22))
        }
    }

    // MARK: Into Home Assistant

    @Test func readingsBecomeARunningTotalInTheServerStatistics() async throws {
        let transport = FakeTransport { message in
            message["type"]?.stringValue == "auth" ? [["type": "auth_ok", "ha_version": "2026.8.1"]] : [result(for: message)]
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()
        let start = parisDate(2026, 10, 21, 0)

        try await connection.importEnergyStatistics(
            id: "maison:grid_consumption",
            name: "Électricité du réseau",
            hourly: [(start.addingTimeInterval(3600), 0.5), (start, 1.5)],
            previousSum: 100
        )

        let sent = try #require(await transport.sentMessages(ofType: "recorder/import_statistics").first)
        #expect(sent["metadata"]?["statistic_id"]?.stringValue == "maison:grid_consumption")
        #expect(sent["metadata"]?["source"]?.stringValue == "maison")
        #expect(sent["metadata"]?["has_sum"]?.boolValue == true)
        #expect(sent["metadata"]?["unit_of_measurement"]?.stringValue == "kWh")
        let stats = sent["stats"]?.arrayValue ?? []
        #expect(stats.map { $0["start"]?.stringValue } == [start.ISO8601Format(), start.addingTimeInterval(3600).ISO8601Format()])
        #expect(stats.map { $0["sum"]?.doubleValue } == [101.5, 102])
    }

    // MARK: The score

    @Test func readingsFromTheDayBeforeScoreYesterdayWhole() throws {
        let midnight = paris.startOfDay(for: parisDate(2026, 10, 22))
        var hourly: [(start: Date, value: Double)] = []
        // Seven full days of 1 kWh an hour, then yesterday at 0.8: nothing for today yet.
        for day in 2...8 {
            for hour in 0..<24 { hourly.append((midnight.addingTimeInterval(Double(-day * 24 + hour) * 3600), 1)) }
        }
        for hour in 0..<24 { hourly.append((midnight.addingTimeInterval(Double(-24 + hour) * 3600), 0.8)) }

        let score = try #require(EnergyScore.compute(hourly: hourly, unit: "kWh", now: midnight.addingTimeInterval(9 * 3600), calendar: paris))

        #expect(score.day == midnight.addingTimeInterval(-86_400))
        #expect(score.asOf == midnight)
        #expect(abs(score.today - 19.2) < 0.0001)
        #expect(score.usual == 24)
        #expect(score.percent == 83)
    }
}
