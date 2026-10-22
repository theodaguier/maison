import Foundation
@testable import Maison
import Testing

struct AnalyticsTests {
    @Test func aMissingTokenSendsNothing() {
        let log = AnalyticsLog(isConfigured: false)
        let analytics = Analytics(client: log, defaults: suite())
        analytics.track(.appOpened)
        analytics.track(.screenViewed(.home))
        analytics.track(.scoreOpened(.energy))
        #expect(log.events.isEmpty)
    }

    @Test func sharingIsOffUntilItIsTurnedOn() {
        let defaults = suite()
        let log = AnalyticsLog(isConfigured: true)
        let analytics = Analytics(client: log, defaults: defaults)
        #expect(!analytics.isEnabled)
        analytics.track(.appOpened)
        #expect(log.events.isEmpty)
        #expect(log.startCount == 0)

        analytics.setEnabled(true)
        let restored = Analytics(client: AnalyticsLog(isConfigured: true), defaults: defaults)
        #expect(restored.isEnabled)

        restored.setEnabled(false)
        let off = AnalyticsLog(isConfigured: true)
        let restoredOff = Analytics(client: off, defaults: defaults)
        #expect(!restoredOff.isEnabled)
        restoredOff.track(.appOpened)
        #expect(off.events.isEmpty)
        #expect(off.startCount == 0)
    }

    @Test func turnedOffSendsNothingAndOnSendsTheEvent() {
        let log = AnalyticsLog(isConfigured: true)
        let analytics = Analytics(client: log, defaults: suite())

        analytics.setEnabled(false)
        analytics.track(.scoreOpened(.comfort))
        #expect(log.events.isEmpty)
        #expect(log.enabled == false)

        analytics.setEnabled(true)
        analytics.track(.scoreOpened(.network))
        analytics.track(.documentScanned(.energyBill))
        analytics.track(.sourceConnected(.homeAssistant))
        #expect(log.enabled == true)
        #expect(log.events.map(\.name) == ["score_opened", "document_scanned", "source_connected"])
        #expect(log.events.map(\.properties) == [
            ["score": "network"],
            ["kind": "energy_bill"],
            ["connector": "home_assistant"],
        ])
    }

    @Test func eventsCarryOnlyTheirToken() {
        let events: [AnalyticsEvent] = [
            .appOpened,
            .screenViewed(.room),
            .scoreOpened(.comfort),
            .scoreOpened(.energy),
            .scoreOpened(.network),
            .sourceConnected(.homeAssistant),
            .documentScanned(.energyBill),
            .documentScanned(.energyContract),
            .documentScanned(.boxBill),
            .documentScanned(.boxContract),
        ]
        #expect(events.map(\.name) == [
            "app_opened", "screen_viewed", "score_opened", "score_opened", "score_opened",
            "source_connected", "document_scanned", "document_scanned", "document_scanned", "document_scanned",
        ])
        for event in events {
            var payload: [String: Any] = [:]
            for (key, value) in event.properties {
                payload[key] = value
            }
            let kept = AnalyticsPayload.filtered(name: event.name, properties: payload)
            #expect(kept?.count == event.properties.count)
            for (key, value) in event.properties {
                #expect(kept?[key] as? String == value)
            }
        }
        #expect(AnalyticsEvent.screenViewed(.room).properties == ["screen": "room"])
        #expect(AnalyticsEvent.appOpened.properties.isEmpty)
    }

    @Test func homeDataIsStrippedBeforeAnythingIsSent() {
        let kept = AnalyticsPayload.filtered(name: "score_opened", properties: [
            "score": "energy",
            "value": "12.4",
            "address": "http://192.168.1.4:8123",
            "device": "Living room lamp",
            "document": "EDF bill March",
            "$device_name": "Kitchen iPhone",
            "$device_id": "vendor-id",
            "$idfa": "00000000-0000-0000-0000-000000000000",
            "$timezone": "Europe/Paris",
            "$screen_name": "Living room",
            "$geoip_disable": true,
            "$process_person_profile": false,
            "$lib": "posthog-ios",
        ])
        #expect(kept?["score"] as? String == "energy")
        #expect(kept?["$geoip_disable"] as? Bool == true)
        #expect(kept?["$process_person_profile"] as? Bool == false)
        #expect(kept?["$lib"] as? String == "posthog-ios")
        let keys = Set((kept ?? [:]).keys)
        #expect(keys == Set(["score", "$geoip_disable", "$process_person_profile", "$lib"]))
    }

    @Test func anUnknownEventOrTokenIsDropped() {
        let unknown = AnalyticsPayload.filtered(name: "lamp_toggled", properties: ["name": "Lamp"])
        #expect(isAbsent(unknown))
        let score = AnalyticsPayload.filtered(name: "score_opened", properties: ["score": "living_room"])
        #expect(score?.isEmpty == true)
        let screen = AnalyticsPayload.filtered(name: "screen_viewed", properties: ["screen": 3])
        #expect(screen?.isEmpty == true)
    }

    @Test func theSDKAllowlistLeavesOutIdentifiers() {
        let forbidden: Set = [
            "$device_name", "$device_id", "$idfa", "$idfv", "$ip", "$timezone",
            "$elements_chain", "$screen_name", "$exception_list", "$set",
        ]
        #expect(AnalyticsPayload.allowedSDKProperties.isDisjoint(with: forbidden))
        #expect(AnalyticsPayload.allowedSDKProperties.contains("$process_person_profile"))
        #expect(AnalyticsPayload.allowedSDKProperties.contains("$geoip_disable"))
    }

    @Test func onlyAProjectTokenCountsAsAKey() {
        #expect(AnalyticsKey.usable(nil) == nil)
        #expect(AnalyticsKey.usable("") == nil)
        #expect(AnalyticsKey.usable("   ") == nil)
        #expect(AnalyticsKey.usable("$(POSTHOG_API_KEY)") == nil)
        #expect(AnalyticsKey.usable(AnalyticsKey.placeholder) == nil)
        #expect(AnalyticsKey.usable("phx_personal_secret") == nil)
        #expect(AnalyticsKey.usable(" not-a-key ") == nil)
        #expect(AnalyticsKey.usable(" phc_project_token ") == "phc_project_token")
    }

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "AnalyticsTests-\(UUID().uuidString)")!
    }

    private func isAbsent(_ value: [String: Any]?) -> Bool {
        if case .none = value { return true }
        return false
    }
}

final class AnalyticsLog: AnalyticsClient, @unchecked Sendable {
    let isConfigured: Bool
    private let lock = NSLock()
    private var captured: [(name: String, properties: [String: String])] = []
    private var recordedEnabled: Bool?

    init(isConfigured: Bool) {
        self.isConfigured = isConfigured
    }

    private var starts = 0

    func start(enabled: Bool) {
        lock.lock()
        starts += 1
        lock.unlock()
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        recordedEnabled = enabled
        lock.unlock()
    }

    func capture(name: String, properties: [String: String]) {
        lock.lock()
        captured.append((name, properties))
        lock.unlock()
    }

    var events: [(name: String, properties: [String: String])] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    var enabled: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return recordedEnabled
    }
}
