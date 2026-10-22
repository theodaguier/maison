import CloudKit
import Foundation
@testable import Maison
import Testing

struct HouseholdMappingTests {
    let zoneID = HouseholdLocation.owned.zoneID
    let household = Household(
        name: "Maison",
        serverURL: URL(string: "http://192.168.1.179:8123")!,
        remoteURL: URL(string: "https://maison.example.ts.net")!
    )

    // MARK: Household

    @Test func householdRoundTripsThroughARecord() {
        let record = household.record(in: zoneID)

        #expect(record.recordType == "Household")
        #expect(record.recordID == Household.recordID(in: zoneID))
        #expect(Household(record: record) == household)
    }

    @Test func householdWithoutRemoteURL() {
        var local = household
        local.remoteURL = nil
        let record = local.record(updating: household.record(in: zoneID), in: zoneID)

        #expect(record["remoteURL"] == nil)
        #expect(Household(record: record) == local)
    }

    @Test func rejectsARecordWithoutAServer() {
        let record = household.record(in: zoneID)
        record["serverURL"] = "not a url"
        #expect(Household(record: record) == nil)

        let other = CKRecord(recordType: "MemberFavorites", recordID: Household.recordID(in: zoneID))
        #expect(Household(record: other) == nil)
    }

    // MARK: Favourites

    @Test func favoritesRoundTripPerMember() {
        let record = MemberFavorites.record(["light.salon", "lock.porte"], for: "_abc", in: zoneID)

        #expect(record.recordID.recordName == "favorites-_abc")
        #expect(record.recordID.zoneID == zoneID)
        #expect(record["memberID"] as? String == "_abc")
        #expect(MemberFavorites.entityIDs(from: record) == ["light.salon", "lock.porte"])
    }

    @Test func emptyFavoritesAreStoredAsNoValue() {
        let previous = MemberFavorites.record(["light.salon"], for: "_abc", in: zoneID)
        let record = MemberFavorites.record([], for: "_abc", updating: previous, in: zoneID)

        #expect(record["entityIDs"] == nil)
        #expect(MemberFavorites.entityIDs(from: record) == [])
    }

    @Test func ignoresARecordOfAnotherType() {
        #expect(MemberFavorites.entityIDs(from: household.record(in: zoneID)) == nil)
    }

    // MARK: Locations

    @Test func ownedHouseholdLivesInThePrivateDatabase() {
        #expect(HouseholdLocation.owned.zoneID == CKRecordZone.ID(zoneName: "Household", ownerName: CKCurrentUserDefaultName))
        #expect(!HouseholdLocation.owned.isShared)
    }

    @Test func sharedHouseholdKeepsTheOwnersZone() {
        let location = HouseholdLocation(sharedZone: CKRecordZone.ID(zoneName: "Household", ownerName: "_owner"))
        #expect(location.isShared)
        #expect(location.zoneID.ownerName == "_owner")
    }

    // MARK: Roles and members

    @Test(arguments: [
        (CKShare.ParticipantRole.owner, HouseholdRole.owner),
        (.administrator, .administrator),
        (.privateUser, .resident),
        (.publicUser, .resident),
        (.unknown, .resident),
    ])
    func mapsShareRoles(_ role: CKShare.ParticipantRole, _ expected: HouseholdRole) {
        #expect(HouseholdRole(role) == expected)
    }

    @Test func invitesWithTheMatchingShareRole() {
        #expect(HouseholdRole.administrator.participantRole == .administrator)
        #expect(HouseholdRole.resident.participantRole == .privateUser)
        #expect(HouseholdRole.owner.canManageMembers)
        #expect(HouseholdRole.administrator.canManageMembers)
        #expect(!HouseholdRole.resident.canManageMembers)
    }

    @Test func memberUsesTheICloudName() {
        var name = PersonNameComponents()
        name.givenName = "Camille"
        name.familyName = "Martin"
        let member = HouseholdMember(
            participantID: "p1", nameComponents: name, email: "camille@icloud.com", phoneNumber: nil,
            role: .administrator, acceptance: .accepted, isCurrentUser: false
        )

        #expect(member.id == "p1")
        #expect(member.name?.contains("Camille") == true)
        #expect(member.role == .administrator)
        #expect(!member.isPending)
    }

    @Test func pendingMemberFallsBackOnTheirContact() {
        let byEmail = HouseholdMember(
            participantID: "p2", nameComponents: PersonNameComponents(), email: "jules@icloud.com", phoneNumber: nil,
            role: .privateUser, acceptance: .pending, isCurrentUser: false
        )
        let byPhone = HouseholdMember(
            participantID: "p3", nameComponents: nil, email: nil, phoneNumber: "+33612345678",
            role: .privateUser, acceptance: .pending, isCurrentUser: false
        )

        #expect(byEmail.name == "jules@icloud.com")
        #expect(byEmail.isPending)
        #expect(byEmail.role == .resident)
        #expect(byPhone.name == "+33612345678")
    }

    @Test func listsTheOwnerFirstAndPendingInvitationsLast() {
        let members = [
            HouseholdMember(id: "1", name: "Zoé", role: .resident),
            HouseholdMember(id: "2", name: "Jules", role: .resident, isPending: true),
            HouseholdMember(id: "3", name: "Théo", role: .owner),
            HouseholdMember(id: "4", name: "Camille", role: .administrator),
            HouseholdMember(id: "5", name: "Alix", role: .resident),
        ]

        #expect(members.sortedForDisplay().map(\.id) == ["3", "4", "5", "1", "2"])
    }
}
