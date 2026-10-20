import Testing
@testable import Maison

struct DeviceKindTests {
    @Test(arguments: [
        ("light.salon_lampadaire", DeviceKind.light),
        ("switch.prise_cafe", .switch),
        ("input_boolean.mode_invites", .switch),
        ("climate.chambre", .climate),
        ("cover.volets_salon", .cover),
        ("media_player.sonos_salon", .mediaPlayer),
        ("binary_sensor.fenetre_chambre", .binarySensor),
        ("water_heater.ballon", .climate),
        ("weather.maison", .other),
    ])
    func kindFromEntityID(entityID: String, expected: DeviceKind) {
        #expect(DeviceKind(entityID: entityID) == expected)
    }

    @Test func quickActionsMatchTheDesign() {
        #expect(DeviceKind.light.quickAction == .gauge)
        #expect(DeviceKind.switch.quickAction == .toggle)
        #expect(DeviceKind.climate.quickAction == .setpoint)
        #expect(DeviceKind.mediaPlayer.quickAction == .playback)
        #expect(DeviceKind.lock.quickAction == .state)
        #expect(DeviceKind.scene.quickAction == .run)
    }
}
