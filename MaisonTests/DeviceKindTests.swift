@testable import Maison
import Testing

struct DeviceKindTests {
    @Test func quickActionsMatchTheDesign() {
        #expect(DeviceKind.light.quickAction == .level)
        #expect(DeviceKind.switch.quickAction == .toggle)
        #expect(DeviceKind.climate.quickAction == .setpoint)
        #expect(DeviceKind.mediaPlayer.quickAction == .playback)
        #expect(DeviceKind.lock.quickAction == .state)
        #expect(DeviceKind.scene.quickAction == .run)
    }
}

struct LevelStepTests {
    @Test(arguments: [
        (0.8, true, 0.9),
        (0.8, false, 0.7),
        (0.83, true, 0.9),
        (0.83, false, 0.8),
        (0.0, true, 0.1),
        (0.1, false, 0.0),
        (1.0, true, 1.0),
        (0.0, false, 0.0),
        (0.97, true, 1.0),
        (0.04, false, 0.0),
    ])
    func stepsSnapToTenPercent(from level: Double, increasing: Bool, expected: Double) {
        #expect(abs(LevelStep.next(from: level, increasing: increasing) - expected) < 1e-9)
    }

    @Test func aLevelAlreadyOnAStepMovesByOneStep() {
        // 153/255 is 60 % in Home Assistant's brightness scale, and 0.1 * 3 is not exactly 0.3.
        #expect(abs(LevelStep.next(from: 153.0 / 255, increasing: true) - 0.7) < 1e-9)
        #expect(abs(LevelStep.next(from: 0.1 * 3, increasing: false) - 0.2) < 1e-9)
    }
}
