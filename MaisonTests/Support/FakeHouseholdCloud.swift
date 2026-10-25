import CloudKit
import Foundation
@testable import Maison

/// In-memory iCloud: one user, households by location, favourites by member.
actor FakeHouseholdCloud: HouseholdCloud {
    private let userID: String?
    private var households: [HouseholdLocation: Household] = [:]
    private var favorites: [String: [String]] = [:]
    private var plans: [HouseholdLocation: FloorPlan] = [:]
    private var participants: [HouseholdLocation: [HouseholdMember]] = [:]
    private var displayNames: [String: String] = [:]
    private(set) var createdCount = 0
    private(set) var savedHouseholds: [Household] = []
    private(set) var invitations: [String] = []
    private var accesses: [String: MemberAccess] = [:]
    private var currentParticipants: [HouseholdLocation: String] = [:]

    init(userID: String? = "_me") {
        self.userID = userID
    }

    /// A household someone else shared with this user.
    func addSharedHousehold(_ household: Household, members: [HouseholdMember]) -> HouseholdLocation {
        let location = HouseholdLocation(zoneName: "Household", ownerName: "_owner", isShared: true)
        households[location] = household
        participants[location] = members
        return location
    }

    /// The current user's participant id in a household shared with them.
    func setCurrentParticipant(_ participantID: String, in location: HouseholdLocation) {
        currentParticipants[location] = participantID
    }

    func storedAccess(of participantID: String, in location: HouseholdLocation) -> MemberAccess? {
        accesses[key(participantID, location)]
    }

    func setMembers(_ members: [HouseholdMember], in location: HouseholdLocation) {
        participants[location] = members
    }

    func setFavorites(_ entityIDs: [String], of memberID: String, in location: HouseholdLocation) {
        favorites[key(memberID, location)] = entityIDs
    }

    func storedFavorites(of memberID: String, in location: HouseholdLocation) -> [String]? {
        favorites[key(memberID, location)]
    }

    // MARK: HouseholdCloud

    func currentUserID() async throws -> String? { userID }

    func findHousehold() async throws -> StoredHousehold? {
        let location = households.keys.first(where: \.isShared) ?? households.keys.first
        return location.map { StoredHousehold(location: $0, household: households[$0]!) }
    }

    func create(_ household: Household) async throws -> HouseholdLocation {
        createdCount += 1
        households[.owned] = household
        return .owned
    }

    func save(_ household: Household, in location: HouseholdLocation) async throws {
        savedHouseholds.append(household)
        households[location] = household
    }

    func favorites(of memberID: String, in location: HouseholdLocation) async throws -> [String]? {
        favorites[key(memberID, location)]
    }

    func floorPlan(in location: HouseholdLocation) async throws -> FloorPlan? {
        plans[location]
    }

    func saveFloorPlan(_ plan: FloorPlan, in location: HouseholdLocation) async throws {
        plans[location] = plan
    }

    func saveFavorites(_ entityIDs: [String], of memberID: String, in location: HouseholdLocation) async throws {
        favorites[key(memberID, location)] = entityIDs
    }

    func members(in location: HouseholdLocation) async throws -> [HouseholdMember] {
        participants[location] ?? []
    }

    func displayNames(of memberIDs: [String], in location: HouseholdLocation) async throws -> [String: String] {
        var names: [String: String] = [:]
        for id in memberIDs {
            if let name = displayNames[key(id, location)] { names[id] = name }
        }
        return names
    }

    func saveDisplayName(_ name: String, of memberID: String, in location: HouseholdLocation) async throws {
        displayNames[key(memberID, location)] = name
    }

    /// The participant id is the contact, so inviting someone again finds them.
    func invite(_ contact: String, to household: Household, in location: HouseholdLocation) async throws -> Invitation {
        invitations.append(contact)
        var members = participants[location] ?? [HouseholdMember(id: "owner", name: "Owner", role: .owner, isCurrentUser: true)]
        if !members.contains(where: { $0.id == contact }) {
            members.append(HouseholdMember(id: contact, name: contact, role: .administrator, isPending: true))
        }
        participants[location] = members
        return Invitation(url: URL(string: "https://www.icloud.com/share/fake")!, participantID: contact, name: contact)
    }

    func currentParticipantID(in location: HouseholdLocation) async throws -> String? {
        currentParticipants[location]
    }

    func memberAccess(of participantID: String, in location: HouseholdLocation) async throws -> MemberAccess? {
        accesses[key(participantID, location)]
    }

    func saveMemberAccess(_ access: MemberAccess, in location: HouseholdLocation) async throws {
        accesses[key(access.participantID, location)] = access
    }

    func deleteMemberAccess(of participantID: String, in location: HouseholdLocation) async throws {
        accesses[key(participantID, location)] = nil
    }

    func remove(_ member: HouseholdMember, from location: HouseholdLocation) async throws {
        participants[location]?.removeAll { $0.id == member.id }
    }

    func accept(_ metadata: CKShare.Metadata) async throws -> HouseholdLocation {
        throw CKError(.notAuthenticated)
    }

    func leave(_ location: HouseholdLocation) async throws {
        households[location] = nil
        participants[location] = nil
    }

    private func key(_ memberID: String, _ location: HouseholdLocation) -> String {
        "\(location.ownerName)/\(location.zoneName)/\(memberID)"
    }
}
