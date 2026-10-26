import Foundation
@testable import Maison
import Testing

/// Clear names, duplicates and suggested rooms: the setup tidied without opening the server's settings.
struct DeviceNamingTests {
    @Test(arguments: [
        ("Salon Lampe", "Salon", "Lampe"),
        ("Lampe Salon", "Salon", "Lampe"),
        ("Lampe du salon", "Salon", "Lampe"),
        ("Living Room Lamp", "Living Room", "Lamp"),
        ("Light in the kitchen", "Kitchen", "Light"),
        ("Entrée spot", "Entree", "Spot"),
        ("Chambre Théo plafonnier", "Chambre Théo", "Plafonnier"),
    ])
    func dropsTheRoomItIsShownIn(name: String, room: String, expected: String) {
        #expect(DeviceNaming.clearName(name, room: room) == expected)
    }

    @Test func keepsANameThatIsOnlyTheRoom() {
        #expect(DeviceNaming.clearName("Salon", room: "Salon") == "Salon")
    }

    @Test func keepsTheRoomInsideALongerWord() {
        #expect(DeviceNaming.clearName("Salonnière lampe", room: "Salon") == "Salonnière lampe")
    }

    @Test func dropsWhatTheIntegrationRepeatedOrAdded() {
        #expect(DeviceNaming.clearName("Prise Prise", room: nil) == "Prise")
        #expect(DeviceNaming.clearName("Lampe Salon Lampe Salon", room: "Salon") == "Lampe")
        #expect(DeviceNaming.clearName("Plug 3C6105E3A1B2", room: nil) == "Plug")
        #expect(DeviceNaming.clearName("Plug A8:03:2A:B1:C2:D4", room: nil) == "Plug")
        // A model name is not an identifier.
        #expect(DeviceNaming.clearName("Shelly 1PM", room: nil) == "Shelly 1PM")
        #expect(DeviceNaming.clearName("Lampe", room: nil) == "Lampe")
    }
}

struct DuplicateEntitiesTests {
    private func light(_ id: String, _ name: String, members: [String]? = nil) -> EntityState {
        var attributes: [String: JSONValue] = ["friendly_name": .string(name)]
        if let members { attributes["entity_id"] = .array(members.map { .string($0) }) }
        return EntityState(entityID: id, state: "on", attributes: attributes)
    }

    @Test func aGroupOfOneIsItsMember() {
        let states = [light("light.lampe", "Lampe"), light("light.groupe", "Groupe", members: ["light.lampe"])]
        #expect(DuplicateEntities.find(in: states, layout: HomeLayout()) == ["light.groupe"])
    }

    @Test func aGroupOfSeveralIsKept() {
        let states = [light("light.a", "A"), light("light.b", "B"), light("light.toutes", "Toutes", members: ["light.a", "light.b"])]
        #expect(DuplicateEntities.find(in: states, layout: HomeLayout()).isEmpty)
    }

    @Test func theSameNameTwiceOnOneDeviceKeepsTheShortestID() {
        var layout = HomeLayout()
        layout.deviceByEntity = ["light.lampe": "d1", "light.lampe_2": "d1"]
        let states = [light("light.lampe_2", "Lampe"), light("light.lampe", "Lampe")]
        #expect(DuplicateEntities.find(in: states, layout: layout) == ["light.lampe_2"])
    }

    @Test func theSameDeviceThroughTwoIntegrationsIsShownOnce() {
        var layout = HomeLayout()
        layout.areaByEntity = ["light.lampe": "salon", "light.lampe_bridge": "salon"]
        layout.deviceByEntity = ["light.lampe": "d1", "light.lampe_bridge": "d2"]
        layout.platformByEntity = ["light.lampe": "hue", "light.lampe_bridge": "homekit_controller"]
        let states = [light("light.lampe", "Lampe"), light("light.lampe_bridge", "Lampe")]
        #expect(DuplicateEntities.find(in: states, layout: layout) == ["light.lampe_bridge"])
    }

    @Test func twoLampsOfOneIntegrationWithTheSameNameAreTwoLamps() {
        var layout = HomeLayout()
        layout.areaByEntity = ["light.spot_1": "salon", "light.spot_2": "salon"]
        layout.deviceByEntity = ["light.spot_1": "d1", "light.spot_2": "d2"]
        layout.platformByEntity = ["light.spot_1": "hue", "light.spot_2": "hue"]
        let states = [light("light.spot_1", "Spot"), light("light.spot_2", "Spot")]
        #expect(DuplicateEntities.find(in: states, layout: layout).isEmpty)
    }

    @MainActor
    @Test func duplicatesLeaveDeviceListsButStayWithTheirIntegration() {
        var layout = HomeLayout()
        layout.platformByEntity = ["light.lampe": "hue", "light.groupe": "group"]
        let store = HomeStore(
            demo: [light("light.lampe", "Lampe"), light("light.groupe", "Groupe", members: ["light.lampe"])],
            layout: layout,
            household: HouseholdStore(cloud: nil, defaults: UserDefaults(suiteName: "Duplicates.\(UUID().uuidString)")!)
        )

        #expect(store.devices.map(\.entityID) == ["light.lampe"])
        #expect(store.devices(of: IntegrationSummary(domain: "group", title: "Group", count: 1)).map(\.entityID) == ["light.groupe"])
    }
}

struct RoomSuggestionTests {
    private func device(_ id: String, _ name: String) -> EntityState {
        EntityState(entityID: id, state: "on", attributes: ["friendly_name": .string(name)])
    }

    @Test func suggestsTheExistingRoomItsNameSays() {
        var layout = HomeLayout()
        layout.areas = [Area(id: "salon", name: "Salon"), Area(id: "chambre_theo", name: "Chambre Théo")]
        layout.areaByEntity = ["light.placed": "salon"]
        let suggestions = RoomSuggestion.suggest(for: [
            device("light.lampe", "Lampe salon"),
            device("light.chevet", "Chevet chambre theo"),
            device("light.placed", "Lampadaire salon"),
            device("light.salonniere", "Salonnière"),
        ], layout: layout)

        #expect(suggestions == [
            RoomSuggestion(areaID: "chambre_theo", roomName: "Chambre Théo", entityIDs: ["light.chevet"]),
            RoomSuggestion(areaID: "salon", roomName: "Salon", entityIDs: ["light.lampe"]),
        ])
    }

    @Test func suggestsMakingARoomTheNameNames() {
        let suggestions = RoomSuggestion.suggest(for: [
            device("light.plafonnier", "Plafonnier cuisine"),
            device("switch.hotte", "Hotte Cuisine"),
            device("light.miroir", "Miroir salle de bain"),
            device("light.lampe", "Lampe"),
        ], layout: HomeLayout())

        #expect(suggestions == [
            RoomSuggestion(areaID: nil, roomName: "Cuisine", entityIDs: ["light.plafonnier", "switch.hotte"]),
            RoomSuggestion(areaID: nil, roomName: "Salle de bain", entityIDs: ["light.miroir"]),
        ])
    }

    @Test func keepsTheRoomWordAsWritten() {
        #expect(RoomKind.roomWord(in: "Spot entrée") == "Entrée")
        #expect(RoomKind.roomWord(in: "Kitchen light") == "Kitchen")
        #expect(RoomKind.roomWord(in: "Halloween lights") == nil)
    }

    @MainActor
    @Test func placesTheDevicesOfASuggestedRoom() async throws {
        let server = fakeHomeServer(
            entities: [
                "light.plafonnier": ["s": "on", "a": ["friendly_name": "Plafonnier cuisine"]],
                "light.spot": ["s": "on", "a": ["friendly_name": "Spot cuisine"]],
                "switch.hotte": ["s": "on", "a": ["friendly_name": "Hotte cuisine"]],
            ],
            replies: [
                "config/entity_registry/list": [
                    ["entity_id": "light.plafonnier", "device_id": "d1"],
                    ["entity_id": "light.spot", "device_id": "d1"],
                    ["entity_id": "switch.hotte"],
                ],
                "config/area_registry/create": ["area_id": "cuisine", "name": "Cuisine"],
            ]
        )
        let store = try FakeHome.store([server])
        await store.connect()
        let suggestion = try #require(store.roomSuggestions.first)
        #expect(suggestion.areaID == nil)

        try await store.place(suggestion)

        let created = await server.sentMessages(ofType: "config/area_registry/create")
        #expect(created.map { $0["name"]?.stringValue } == ["Cuisine"])
        // One device, set once; the entity without a device gets its own room.
        let devices = await server.sentMessages(ofType: "config/device_registry/update")
        #expect(devices.map { $0["device_id"]?.stringValue } == ["d1"])
        #expect(devices.map { $0["area_id"]?.stringValue } == ["cuisine"])
        let entities = await server.sentMessages(ofType: "config/entity_registry/update")
        #expect(entities.map { $0["entity_id"]?.stringValue } == ["switch.hotte"])
        #expect(entities.map { $0["area_id"]?.stringValue } == ["cuisine"])
    }
}
