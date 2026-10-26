import Foundation
@testable import Maison
import Testing

/// The log's own tests are in the intelligence layer; where the iPhone keeps it is tested here.
struct HousekeepingLogStorageTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theLogIsKeptAndReadsAnOlderOne() throws {
        let defaults = try #require(UserDefaults(suiteName: "Housekeeping-\(UUID().uuidString)"))
        var log = HousekeepingLog()
        log.markDone(.floors, in: "cuisine", at: now)
        log.kinds["arriere"] = .laundry
        log.save(to: defaults)
        #expect(HousekeepingLog.load(from: defaults) == log)

        defaults.set(Data(#"{"done":{}}"#.utf8), forKey: HousekeepingLog.key)
        #expect(HousekeepingLog.load(from: defaults) == HousekeepingLog())
    }
}

@MainActor
struct HousekeepingStoreTests {
    @Test func theDemoAsksAboutTheRoomItCannotName() throws {
        let store = DemoHome.store()
        let question = try #require(store.roomToConfirm)
        #expect(question.area.id == "back_room")
        #expect(question.guess.basis == .nothing)

        store.chooseKind(.laundry, for: question.area)
        #expect(store.roomKind(question.area) == .laundry)
        #expect(store.roomToConfirm == nil)
        #expect(store.chores(in: question.area).map(\.chore) == [.floors])
    }

    @Test func theDemoBathroomIsLateAndDoneClearsIt() throws {
        let store = DemoHome.store()
        let bathroom = try #require(store.layout.areas.first { $0.id == "bathroom" })
        #expect(store.roomKind(bathroom) == .bathroom)
        #expect(store.chores(in: bathroom).allSatisfy { $0.isLate() })
        #expect(store.allChores().first?.roomID == "bathroom")

        store.markDone(.shower, in: bathroom)
        let shower = try #require(store.chores(in: bathroom).first { $0.chore == .shower })
        #expect(!shower.isLate())
        #expect(shower.origin == .entered)
    }

    @Test func doneShowsAsDoneTodayAndUndoPutsItBack() throws {
        let store = DemoHome.store()
        let bathroom = try #require(store.layout.areas.first { $0.id == "bathroom" })
        let before = try #require(store.chores(in: bathroom).first { $0.chore == .sink })
        #expect(!before.isDoneToday)

        let previous = store.markDone(.sink, in: bathroom)
        #expect(previous == before.lastDone)
        #expect(store.chores(in: bathroom).first { $0.chore == .sink }?.isDoneToday == true)

        store.undoDone(.sink, in: bathroom, previous: previous)
        let after = try #require(store.chores(in: bathroom).first { $0.chore == .sink })
        #expect(after.lastDone == before.lastDone)
        #expect(after.isLate())
    }

    @Test func theDemoRobotIsFoundAndStarts() async throws {
        let store = DemoHome.store()
        let robot = try #require(store.robotVacuum)
        #expect(robot.entityID == "vacuum.robot")
        await store.startRobot()
        #expect(store.robotVacuum?.state == "cleaning")
    }
}
