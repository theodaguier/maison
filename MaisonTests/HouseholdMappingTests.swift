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

    @Test func ownersAndAdministratorsManageMembers() {
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

    @Test func theCurrentUserAndTheOwnerAreNeverInvitations() {
        let currentUser = HouseholdMember(
            participantID: "_me", nameComponents: nil, email: nil, phoneNumber: nil,
            role: .owner, acceptance: .pending, isCurrentUser: true
        )
        #expect(!currentUser.isPending)
        #expect(!currentUser.showsAsInvitation)
        #expect(currentUser.resolvedName(accountName: "Théo") == "Théo")
        #expect(currentUser.initials(accountName: "Théo") == "T")
        #expect(currentUser.resolvedName(accountName: "  ") == nil)
        #expect(currentUser.initials(accountName: nil) == nil)

        // CloudKit often reports the owner as unknown, and on iOS 26 their name is missing.
        let owner = HouseholdMember(
            participantID: "owner", nameComponents: nil, email: nil, phoneNumber: nil,
            role: .owner, acceptance: .unknown, isCurrentUser: false
        )
        #expect(!owner.isPending)
        #expect(!owner.showsAsInvitation)
        #expect(owner.resolvedName(accountName: "Théo") == nil)

        var name = PersonNameComponents()
        name.givenName = "Camille"
        name.familyName = "Martin"
        let joined = HouseholdMember(
            participantID: "c", nameComponents: name, email: "camille@icloud.com", phoneNumber: nil,
            role: .privateUser, acceptance: .pending, isCurrentUser: true
        )
        #expect(!joined.isPending)
        #expect(joined.name?.contains("Camille") == true)
        #expect(joined.contact == "camille@icloud.com")
        #expect(HouseholdMember(id: "named", name: "Camille Martin", role: .resident).initials(accountName: nil) == "CM")

        let accepted = HouseholdMember(
            participantID: "a", nameComponents: nil, email: nil, phoneNumber: nil,
            role: .administrator, acceptance: .accepted, isCurrentUser: false
        )
        #expect(!accepted.isPending)
        #expect(!accepted.showsAsInvitation)
        #expect(accepted.resolvedName(accountName: "Théo") == nil)

        #expect(!HouseholdMember.isPendingInvitation(role: .administrator, acceptance: .pending, isCurrentUser: true))
        #expect(!HouseholdMember.isPendingInvitation(role: .owner, acceptance: .pending, isCurrentUser: false))
        #expect(!HouseholdMember.isPendingInvitation(role: .privateUser, acceptance: .unknown, isCurrentUser: false))
        #expect(HouseholdMember.isPendingInvitation(role: .privateUser, acceptance: .pending, isCurrentUser: false))
    }

    @Test func aRealInvitationKeepsItsContactAndStaysPending() {
        let invite = HouseholdMember(
            participantID: "j", nameComponents: nil, email: "jules@icloud.com", phoneNumber: nil,
            role: .privateUser, acceptance: .pending, isCurrentUser: false
        )
        let byPhone = HouseholdMember(
            participantID: "p", nameComponents: nil, email: nil, phoneNumber: "+33612345678",
            role: .privateUser, acceptance: .pending, isCurrentUser: false
        )

        #expect(invite.isPending)
        #expect(invite.showsAsInvitation)
        #expect(invite.name == "jules@icloud.com")
        #expect(invite.invitationContact == "jules@icloud.com")
        #expect(invite.initials(accountName: "Théo") == "J")
        #expect(invite.resolvedName(accountName: "Théo") == "jules@icloud.com")
        #expect(byPhone.invitationContact == "+33612345678")
        #expect(byPhone.initials(accountName: nil) == "3")
    }

    @Test func aStoredPendingFlagOnTheCurrentUserIsCorrected() {
        let wrong = HouseholdMember(id: "me", name: nil, role: .administrator, isPending: true, isCurrentUser: true)
        let owner = HouseholdMember(id: "owner", name: nil, role: .owner, isPending: true)
        let invite = HouseholdMember(id: "j", name: "jules@icloud.com", role: .resident, isPending: true)

        #expect(!wrong.normalized.isPending)
        #expect(!wrong.showsAsInvitation)
        #expect(wrong.resolvedName(accountName: "Ada Lovelace") == "Ada Lovelace")
        #expect(wrong.initials(accountName: "Ada Lovelace") == "AL")
        #expect(!owner.showsAsInvitation)
        #expect(invite.normalized.isPending)
        #expect([owner, invite].sortedForDisplay().map(\.id) == ["owner", "j"])
    }

    @Test func removedParticipantsLeaveAndThePrivateOwnerIsTheCurrentUser() {
        #expect(!HouseholdMember.belongsInHousehold(role: .privateUser, acceptance: .removed, isCurrentUser: false))
        #expect(HouseholdMember.belongsInHousehold(role: .owner, acceptance: .removed, isCurrentUser: false))
        #expect(HouseholdMember.belongsInHousehold(role: .privateUser, acceptance: .accepted, isCurrentUser: false))

        #expect(HouseholdMember.matchesCurrentUser(
            role: .owner, participantRecordName: nil, currentUserRecordName: nil,
            matchesCurrentParticipant: false, inPrivateDatabase: true
        ))
        #expect(!HouseholdMember.matchesCurrentUser(
            role: .owner, participantRecordName: nil, currentUserRecordName: nil,
            matchesCurrentParticipant: false, inPrivateDatabase: false
        ))
        #expect(HouseholdMember.matchesCurrentUser(
            role: .privateUser, participantRecordName: "_me", currentUserRecordName: "_me",
            matchesCurrentParticipant: false, inPrivateDatabase: false
        ))
        #expect(!HouseholdMember.matchesCurrentUser(
            role: .administrator, participantRecordName: nil, currentUserRecordName: "_me",
            matchesCurrentParticipant: false, inPrivateDatabase: false
        ))
        #expect(HouseholdMember.matchesCurrentUser(
            role: .privateUser, participantRecordName: "other", currentUserRecordName: "_me",
            matchesCurrentParticipant: true, inPrivateDatabase: false
        ))
    }

    @Test func aChosenDisplayNameRoundTrips() {
        let record = MemberProfile.record("Théo", for: "_me", in: zoneID)
        #expect(record.recordType == "MemberProfile")
        #expect(record.recordID.recordName == "profile-_me")
        #expect(MemberProfile.displayName(from: record) == "Théo")

        let cleared = MemberProfile.record("   ", for: "_me", updating: record, in: zoneID)
        #expect(MemberProfile.displayName(from: cleared) == nil)
        #expect(MemberProfile.displayName(from: household.record(in: zoneID)) == nil)
    }
}
