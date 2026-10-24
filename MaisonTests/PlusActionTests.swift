import Foundation
@testable import Maison
import Testing

@MainActor
struct PlusActionTests {
    @Test func theDemoHomeOffersEveryActionThatWorksThere() {
        let store = DemoHome.store()
        let available = PlusAction.allCases.filter { $0.isAvailable(in: store) }
        // Describing a rule needs Apple Intelligence, which the test simulator may not have.
        #expect(Set(available).isSuperset(of: [.leaving, .addDevice, .newRule, .scene, .turnOff, .search]))
    }

    @Test func everyActionHasASymbolAndATitle() {
        for action in PlusAction.allCases {
            #expect(!action.symbol.isEmpty)
            #expect(!action.title.isEmpty)
        }
    }

    // MARK: Shortcuts

    @Test func theFirstSetFollowsTheMockUpThenTheFavourites() {
        let shortcuts = ShortcutList.starting(favorites: ["switch.prise_cafe", "scene.bonne_nuit", "light.a", "light.b", "light.c"])
        #expect(shortcuts.prefix(6) == [.action(.describeRule), .action(.leaving), .action(.scene), .action(.addDevice), .action(.newRule), .action(.turnOff)])
        #expect(shortcuts.contains(.entity("switch.prise_cafe")))
        // One slot stays free for "Add".
        #expect(shortcuts.count == ShortcutList.capacity - 1)
    }

    @Test func shortcutsSplitIntoPagesOfSix() {
        #expect(ShortcutList.pages(Array(0..<6)).map(\.count) == [6])
        #expect(ShortcutList.pages(Array(0..<7)).map(\.count) == [6, 1])
        #expect(ShortcutList.pages(Array(0..<12)).map(\.count) == [6, 6])
        #expect(ShortcutList.pages([Int]()).isEmpty)
    }

    @Test func shortcutsAreKeptAndCappedAtTwelve() throws {
        let defaults = try #require(UserDefaults(suiteName: "Shortcuts-\(UUID().uuidString)"))
        #expect(ShortcutList.load(from: defaults) == nil)
        let many = (0..<15).map { Shortcut.entity("light.l\($0)") }
        ShortcutList.save([.action(.search)] + many, to: defaults)
        let loaded = try #require(ShortcutList.load(from: defaults))
        #expect(loaded.count == 12)
        #expect(loaded.first == .action(.search))
    }

    @Test func aPinnedDeviceSceneOrRuleShowsOnlyWhileItExists() {
        let store = DemoHome.store()
        #expect(store.isAvailable(.entity("scene.cinema")))
        #expect(!store.isAvailable(.entity("light.gone")))
    }

    // MARK: Leaving

    private func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
        EntityState(entityID: id, state: state, attributes: attributes)
    }

    @Test func leavingListsWhatOnlyThePersonCanDo() {
        let plan = LeavingPlan(devices: [
            entity("binary_sensor.fenetre", "on", ["device_class": "window"]),
            entity("binary_sensor.porte_garage", "off", ["device_class": "garage_door"]),
            entity("binary_sensor.mouvement", "on", ["device_class": "motion"]),
            entity("lock.entree", "unlocked"),
            entity("lock.cave", "locked"),
        ])
        #expect(plan.toSettle.map(\.entityID) == ["binary_sensor.fenetre", "lock.entree"])
    }

    @Test func leavingTurnsOffWhatMaisonCanAndNothingElse() {
        let plan = LeavingPlan(devices: [
            entity("light.salon", "on"),
            entity("light.cuisine", "off"),
            entity("climate.salon", "heat", ["preset_modes": ["none", "eco", "away"], "preset_mode": "none"]),
            entity("climate.chambre", "heat", ["preset_modes": ["none", "comfort"]]),
            entity("climate.bureau", "heat", ["preset_modes": ["eco"], "preset_mode": "eco"]),
            entity("water_heater.ballon", "electric"),
            entity("media_player.sonos", "playing"),
            entity("media_player.tv", "off"),
        ])
        #expect(plan.lights.map(\.entityID) == ["light.salon"])
        // Away first; a thermostat without such a preset, or already in it, is left alone.
        #expect(plan.climate.map(\.entity.entityID) == ["climate.salon"])
        #expect(plan.climate.map(\.preset) == ["away"])
        #expect(plan.waterHeaters.map(\.entityID) == ["water_heater.ballon"])
        #expect(plan.media.map(\.entityID) == ["media_player.sonos"])
        #expect(!plan.isEmpty)
    }

    @Test func leavingAnEmptyHomeHasNothingToDo() {
        let plan = LeavingPlan(devices: [entity("light.salon", "off")])
        #expect(plan.isEmpty)
        #expect(plan.toSettle.isEmpty)
    }

    @Test func turningAwayModeOnRunsThePlanOnTheDemoHome() async {
        let store = DemoHome.store()
        let before = store.devices.filter { $0.kind == .light && $0.state == "on" }
        #expect(!before.isEmpty)
        await LeavingPlan(devices: store.devices).run(on: store)
        #expect(store.devices.filter { $0.kind == .light && $0.state == "on" }.isEmpty)
    }
}
