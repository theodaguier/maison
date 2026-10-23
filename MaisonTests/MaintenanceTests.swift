import Foundation
@testable import Maison
import Testing

struct MaintenanceTests {
    @Test func aWornFilterAsksForCleaning() {
        #expect(MaintenanceItem.signal(entityID: "sensor.clim_filtre", state: "8", deviceClass: nil, unit: "%", translationKey: "filter_life")
            == .filter(remaining: 8))
        #expect(MaintenanceItem.signal(entityID: "sensor.clim_filtre", state: "60", deviceClass: nil, unit: "%", translationKey: "filter_life") == nil)
        #expect(MaintenanceItem.signal(entityID: "binary_sensor.purificateur", state: "on", deviceClass: nil, unit: nil, translationKey: "replace_filter")
            == .filter(remaining: 0))
    }

    @Test func aLowBatteryAndAReportedProblemAreUpkeep() {
        #expect(MaintenanceItem.signal(entityID: "sensor.capteur_battery", state: "12", deviceClass: "battery", unit: "%", translationKey: nil)
            == .battery(level: 12))
        #expect(MaintenanceItem.signal(entityID: "sensor.capteur_battery", state: "80", deviceClass: "battery", unit: "%", translationKey: nil) == nil)
        #expect(MaintenanceItem.signal(entityID: "binary_sensor.lave_linge", state: "on", deviceClass: "problem", unit: nil, translationKey: nil) == .problem)
        #expect(MaintenanceItem.signal(entityID: "binary_sensor.lave_linge", state: "off", deviceClass: "problem", unit: nil, translationKey: nil) == nil)
    }

    @Test func aNameIsNeverEnough() {
        // A percentage sensor called "filter" without the registry saying so isn't upkeep.
        #expect(MaintenanceItem.signal(entityID: "sensor.filtre", state: "5", deviceClass: nil, unit: "%", translationKey: nil) == nil)
    }

    @Test func doneHidesItUntilTheDeviceReportsSomethingNew() throws {
        let defaults = try #require(UserDefaults(suiteName: "Upkeep-\(UUID().uuidString)"))
        let item = MaintenanceItem(id: "sensor.capteur_battery", kind: .battery(level: 12), deviceName: "Capteur", areaID: nil, resetButton: nil)
        #expect(!MaintenanceAcknowledgement.isDone(item, state: "12", in: defaults))
        MaintenanceAcknowledgement.markDone(item, state: "12", in: defaults)
        #expect(MaintenanceAcknowledgement.isDone(item, state: "12", in: defaults))
        #expect(!MaintenanceAcknowledgement.isDone(item, state: "9", in: defaults))
    }

    @MainActor
    @Test func theDemoAirConditionerReportsItsFilterInTheBedroom() {
        let store = DemoHome.store()
        let bedroom = Area(id: "bedroom", name: "Chambre")
        let upkeep = store.maintenance(in: bedroom)
        #expect(upkeep.map(\.kind).contains(.filter(remaining: 8)))
        #expect(upkeep.first { $0.kind == .filter(remaining: 8) }?.resetButton == "button.climatiseur_reset_filter")
        #expect(upkeep.first { $0.kind == .filter(remaining: 8) }?.deviceName == "Climatiseur")
    }
}
