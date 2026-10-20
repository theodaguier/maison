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
    private(set) var createdCount = 0
    private(set) var savedHouseholds: [Household] = []
    private(set) var invitations: [(contact: String, role: HouseholdRole)] = []

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

    func invite(_ contact: String, as role: HouseholdRole, to household: Household, in location: HouseholdLocation) async throws -> URL {
        invitations.append((contact, role))
        var members = participants[location] ?? [HouseholdMember(id: "owner", name: "Owner", role: .owner, isCurrentUser: true)]
        members.append(HouseholdMember(id: contact, name: contact, role: role, isPending: true))
        participants[location] = members
        return URL(string: "https://www.icloud.com/share/fake")!
    }

    func setRole(_ role: HouseholdRole, of member: HouseholdMember, in location: HouseholdLocation) async throws {
        guard let index = participants[location]?.firstIndex(where: { $0.id == member.id }) else { return }
        let old = participants[location]![index]
        participants[location]![index] = HouseholdMember(id: old.id, name: old.name, role: role, isPending: old.isPending, isCurrentUser: old.isCurrentUser)
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
