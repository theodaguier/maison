import Foundation
@testable import Maison
import Testing

struct DiscoveredServerTests {
    @Test func readsHomeAssistantTXTRecord() throws {
        let server = try #require(DiscoveredServer(txtRecord: [
            "location_name": "Home",
            "uuid": "2b54fda4",
            "version": "2026.8.1",
            "external_url": "",
            "internal_url": "http://192.168.1.179:8123",
            "base_url": "http://192.168.1.179:8123",
        ]))

        #expect(server.id == "2b54fda4")
        #expect(server.name == "Home")
        #expect(server.version == "2026.8.1")
        #expect(server.url == URL(string: "http://192.168.1.179:8123"))
    }

    @Test func fallsBackToTheExternalURL() throws {
        let server = try #require(DiscoveredServer(txtRecord: ["external_url": "https://home.example.com"]))
        #expect(server.url.host() == "home.example.com")
        #expect(server.name == "home.example.com")
    }

    @Test func ignoresRecordsWithoutAnyURL() {
        #expect(DiscoveredServer(txtRecord: ["location_name": "Home", "internal_url": ""]) == nil)
    }
}

struct DeviceCommandTests {
    @Test(arguments: [
        (EntityState(entityID: "light.desk", state: "on"), DeviceCommand(domain: "light", service: "toggle")),
        (EntityState(entityID: "input_boolean.guest_mode", state: "off"), DeviceCommand(domain: "input_boolean", service: "toggle")),
        (EntityState(entityID: "lock.front_door", state: "locked"), DeviceCommand(domain: "lock", service: "unlock")),
        (EntityState(entityID: "lock.front_door", state: "unlocked"), DeviceCommand(domain: "lock", service: "lock")),
        (EntityState(entityID: "media_player.living_room", state: "playing"), DeviceCommand(domain: "media_player", service: "media_play_pause")),
        (EntityState(entityID: "scene.movie_night", state: "unknown"), DeviceCommand(domain: "scene", service: "turn_on")),
        (EntityState(entityID: "button.restart", state: "unknown"), DeviceCommand(domain: "button", service: "press")),
    ])
    func primaryAction(entity: EntityState, expected: DeviceCommand) {
        #expect(DeviceCommand(primaryActionFor: entity) == expected)
    }

    @Test func readOnlyDevicesHaveNoPrimaryAction() {
        #expect(DeviceCommand(primaryActionFor: EntityState(entityID: "sensor.temperature", state: "21")) == nil)
        #expect(DeviceCommand(primaryActionFor: EntityState(entityID: "climate.bedroom", state: "heat")) == nil)
    }
}

struct JSONValueTests {
    @Test func roundTripsNestedValues() throws {
        let value: JSONValue = ["on": true, "level": 0.5, "name": "Desk", "tags": ["a", nil], "nested": ["n": 3]]
        let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }

    @Test func keepsBooleansDistinctFromNumbers() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(#"[true, 1, 0]"#.utf8))
        #expect(decoded == [true, 1, 0])
    }
}
