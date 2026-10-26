import Foundation
@testable import MaisonIntelligence
import Testing

struct RoomKindTests {
    @Test func theIconWinsOverTheName() {
        let guess = RoomKind.recognize(name: "Pièce du fond", icon: "mdi:washing-machine")
        #expect(guess == RoomKindGuess(kind: .laundry, basis: .icon))
        #expect(guess.isSure)
    }

    @Test func theNameIsReadInSeveralLanguagesWithoutAccents() {
        #expect(RoomKind.recognize(name: "Salle de bain", icon: nil).kind == .bathroom)
        #expect(RoomKind.recognize(name: "Séjour", icon: nil).kind == .livingRoom)
        #expect(RoomKind.recognize(name: "ENTRÉE", icon: nil).kind == .entrance)
        #expect(RoomKind.recognize(name: "Kitchen", icon: nil).kind == .kitchen)
        #expect(RoomKind.recognize(name: "Chambre de Jules", icon: "mdi:bed-king").basis == .icon)
        #expect(RoomKind.recognize(name: "Salle d’eau", icon: nil).kind == .bathroom)
    }

    @Test func devicesAloneAreAGuessToConfirm() {
        let guess = RoomKind.recognize(name: "Arrière", icon: nil, hints: [.lock])
        #expect(guess == RoomKindGuess(kind: .entrance, basis: .devices))
        #expect(!guess.isSure)
        #expect(RoomKind.recognize(name: "Arrière", icon: nil) == RoomKindGuess(kind: .other, basis: .nothing))
    }

    @Test func choresBelongToRoomsNeverToObjects() {
        // Every type proposes something, and nothing names an appliance or a piece of furniture.
        for kind in RoomKind.allCases { #expect(!kind.chores.isEmpty) }
        #expect(RoomKind.kitchen.chores.map(\.chore) == [.worktop, .floors])
        #expect(RoomKind.bathroom.chores.allSatisfy { $0.days == 7 })
    }
}

struct HousekeepingLogTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func aNewRoomStartsHalfWayThroughItsRhythm() {
        var log = HousekeepingLog()
        log.noteSeen(["salon"], at: now)
        let vacuum = log.statuses(roomID: "salon", kind: .livingRoom, signals: RoomSignals(), now: now).first { $0.chore == .vacuum }
        #expect(vacuum?.origin == .estimated)
        #expect(vacuum?.daysLeft(now: now, calendar: calendar) == 3)
        #expect(vacuum?.isLate(now: now, calendar: calendar) == false)
    }

    @Test func doneIsEnteredAndSetsTheNextOne() {
        var log = HousekeepingLog()
        log.noteSeen(["sdb"], at: now.addingTimeInterval(-30 * 86_400))
        log.markDone(.shower, in: "sdb", at: now.addingTimeInterval(-9 * 86_400))
        let statuses = log.statuses(roomID: "sdb", kind: .bathroom, signals: RoomSignals(), now: now)
        let shower = statuses.first { $0.chore == .shower }
        #expect(shower?.origin == .entered)
        #expect(shower?.daysLeft(now: now, calendar: calendar) == -2)
        #expect(shower?.remaining(now: now) == 0)
        // Soonest first: the chores never marked are older still.
        #expect(statuses.first?.chore != .shower)

        log.markDone(.shower, in: "sdb", at: now)
        let again = log.statuses(roomID: "sdb", kind: .bathroom, signals: RoomSignals(), now: now).first { $0.chore == .shower }
        #expect(again?.daysLeft(now: now, calendar: calendar) == 7)
        #expect(again?.remaining(now: now) == 1)
    }

    @Test func aHumidBathroomBringsTheShowerForward() {
        let humid = RoomSignals(humidity: 74)
        #expect(Chore.shower.rhythm(usual: 7, signals: humid).days == 3)
        #expect(Chore.shower.rhythm(usual: 7, signals: humid).reason == .humidity(74))
        #expect(Chore.towels.rhythm(usual: 7, signals: humid).reason == nil)
        #expect(Chore.shower.rhythm(usual: 7, signals: RoomSignals(humidity: 60)).reason == nil)
    }

    @Test func dustBringsVacuumingForward() {
        let dusty = RoomSignals(particles: 31)
        #expect(Chore.vacuum.rhythm(usual: 7, signals: dusty).days == 3)
        #expect(Chore.vacuum.rhythm(usual: 7, signals: dusty).reason == .particles(31))
        #expect(Chore.sheets.rhythm(usual: 7, signals: dusty).reason == nil)
        #expect(Chore.worktop.rhythm(usual: 1, signals: dusty).days == 1)
    }
}
