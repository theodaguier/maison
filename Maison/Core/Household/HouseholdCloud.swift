import CloudKit
import Foundation
import MachO

/// A household found in iCloud, with where its records live.
struct StoredHousehold: Sendable, Hashable {
    let location: HouseholdLocation
    let household: Household
}

/// Everything the app asks of iCloud, behind a protocol so tests don't need an account.
protocol HouseholdCloud: Sendable {
    /// The iCloud user's record name, or `nil` when no iCloud account is usable.
    func currentUserID() async throws -> String?
    /// A household shared with the user first, then the user's own one.
    func findHousehold() async throws -> StoredHousehold?
    /// Creates the zone in the user's private database and saves the household in it.
    func create(_ household: Household) async throws -> HouseholdLocation
    func save(_ household: Household, in location: HouseholdLocation) async throws
    /// `nil` when the member never saved favourites in this household.
    func favorites(of memberID: String, in location: HouseholdLocation) async throws -> [String]?
    func saveFavorites(_ entityIDs: [String], of memberID: String, in location: HouseholdLocation) async throws
    /// The scanned plan of the home, shared by every member.
    func floorPlan(in location: HouseholdLocation) async throws -> FloorPlan?
    func saveFloorPlan(_ plan: FloorPlan, in location: HouseholdLocation) async throws
    /// The share's participants, or an empty list when nobody was ever invited.
    func members(in location: HouseholdLocation) async throws -> [HouseholdMember]
    /// Names members chose to show. Missing records are left out. Not an Apple ID identity.
    func displayNames(of memberIDs: [String], in location: HouseholdLocation) async throws -> [String: String]
    func saveDisplayName(_ name: String, of memberID: String, in location: HouseholdLocation) async throws
    /// Adds the person to the household's share with `role` and returns the link to send them.
    func invite(_ contact: String, as role: HouseholdRole, to household: Household, in location: HouseholdLocation) async throws -> URL
    func remove(_ member: HouseholdMember, from location: HouseholdLocation) async throws
    func setRole(_ role: HouseholdRole, of member: HouseholdMember, in location: HouseholdLocation) async throws
    func accept(_ metadata: CKShare.Metadata) async throws -> HouseholdLocation
    /// Stops participating in a household someone else shared.
    func leave(_ location: HouseholdLocation) async throws
}

enum HouseholdError: LocalizedError, Equatable {
    case invalidContact
    case noShareLink

    var errorDescription: String? {
        switch self {
        case .invalidContact: String(localized: "Enter an email address or a phone number.")
        case .noShareLink: String(localized: "iCloud didn’t return an invitation link. Try again.")
        }
    }
}

/// The CloudKit implementation: one zone per household, shared as a whole with a zone-wide `CKShare`.
struct CloudKitHousehold: HouseholdCloud {
    static let containerIdentifier = "iCloud.com.theodaguier.maison"

    /// Created on first use: building a container needs the iCloud entitlement.
    private static let container = CKContainer(identifier: containerIdentifier)

    /// Whether the app is signed for iCloud. CloudKit traps when a container is created without the
    /// entitlement, as in unsigned simulator builds (`CODE_SIGNING_ALLOWED=NO`, used for tests and CI).
    static let isEntitled: Bool = {
        #if targetEnvironment(simulator)
        // The simulator reads entitlements from a section of the executable rather than a signature.
        guard let header = _dyld_get_image_header(0) else { return false }
        var size: UInt = 0
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard let data = getsectiondata(header64, "__TEXT", "__entitlements", &size) else { return false }
        let plist = String(decoding: UnsafeBufferPointer(start: data, count: Int(size)), as: UTF8.self)
        return plist.contains(containerIdentifier)
        #else
        return true
        #endif
    }()

    private var container: CKContainer { Self.container }

    /// Reads an invitation link (scanned or pasted) as iOS does when the link is tapped.
    static func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await container.shareMetadata(for: url)
    }

    /// Whether this iPhone is signed in to iCloud, which household sharing needs.
    static func isAccountAvailable() async -> Bool {
        guard isEntitled else { return false }
        return (try? await container.accountStatus()) == .available
    }

    func currentUserID() async throws -> String? {
        guard try await container.accountStatus() == .available else { return nil }
        return try await container.userRecordID().recordName
    }

    func findHousehold() async throws -> StoredHousehold? {
        let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
        for zone in sharedZones where zone.zoneID.zoneName == HouseholdLocation.owned.zoneName {
            let location = HouseholdLocation(sharedZone: zone.zoneID)
            if let household = try await household(in: location) {
                return StoredHousehold(location: location, household: household)
            }
        }
        let location = HouseholdLocation.owned
        return try await household(in: location).map { StoredHousehold(location: location, household: $0) }
    }

    func create(_ household: Household) async throws -> HouseholdLocation {
        let location = HouseholdLocation.owned
        let (results, _) = try await container.privateCloudDatabase.modifyRecordZones(
            saving: [CKRecordZone(zoneID: location.zoneID)], deleting: []
        )
        _ = try results[location.zoneID]?.get()
        try await save(household, in: location)
        return location
    }

    func save(_ household: Household, in location: HouseholdLocation) async throws {
        try await save(household.record(in: location.zoneID), in: location)
    }

    func favorites(of memberID: String, in location: HouseholdLocation) async throws -> [String]? {
        try await record(MemberFavorites.recordID(for: memberID, in: location.zoneID), in: location)
            .flatMap(MemberFavorites.entityIDs(from:))
    }

    func saveFavorites(_ entityIDs: [String], of memberID: String, in location: HouseholdLocation) async throws {
        try await save(MemberFavorites.record(entityIDs, for: memberID, in: location.zoneID), in: location)
    }

    func floorPlan(in location: HouseholdLocation) async throws -> FloorPlan? {
        try await record(FloorPlanRecord.recordID(in: location.zoneID), in: location).flatMap(FloorPlanRecord.plan(from:))
    }

    func saveFloorPlan(_ plan: FloorPlan, in location: HouseholdLocation) async throws {
        try await save(FloorPlanRecord.record(plan, in: location.zoneID), in: location)
    }

    func members(in location: HouseholdLocation) async throws -> [HouseholdMember] {
        guard let share = try await share(in: location) else { return [] }
        // currentUserParticipant is missing on some private-database shares, and on iOS 26 the
        // owner's user record id is nil without the extended share-access entitlement.
        let currentRecordName = try? await container.userRecordID().recordName
        let current = share.currentUserParticipant
        return share.participants.compactMap { participant in
            let isCurrent = HouseholdMember.matchesCurrentUser(
                role: participant.role,
                participantRecordName: participant.userIdentity.userRecordID?.recordName,
                currentUserRecordName: currentRecordName,
                matchesCurrentParticipant: current.map { participant == $0 } ?? false,
                inPrivateDatabase: !location.isShared
            )
            guard HouseholdMember.belongsInHousehold(
                role: participant.role,
                acceptance: participant.acceptanceStatus,
                isCurrentUser: isCurrent
            ) else { return nil }
            return HouseholdMember(participant, isCurrentUser: isCurrent)
        }
    }

    func displayNames(of memberIDs: [String], in location: HouseholdLocation) async throws -> [String: String] {
        var names: [String: String] = [:]
        for id in memberIDs {
            let recordID = MemberProfile.recordID(for: id, in: location.zoneID)
            if let name = try await record(recordID, in: location).flatMap(MemberProfile.displayName(from:)) {
                names[id] = name
            }
        }
        return names
    }

    func saveDisplayName(_ name: String, of memberID: String, in location: HouseholdLocation) async throws {
        let existing = try await record(MemberProfile.recordID(for: memberID, in: location.zoneID), in: location)
        try await save(MemberProfile.record(name, for: memberID, updating: existing, in: location.zoneID), in: location)
    }

    func invite(_ contact: String, as role: HouseholdRole, to household: Household, in location: HouseholdLocation) async throws -> URL {
        let contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contact.isEmpty else { throw HouseholdError.invalidContact }
        let share = try await share(in: location) ?? {
            let share = CKShare(recordZoneID: location.zoneID)
            share.publicPermission = .none
            return share
        }()
        share[CKShare.SystemFieldKey.title] = household.name

        let participant = contact.contains("@")
            ? try await container.shareParticipant(forEmailAddress: contact)
            : try await container.shareParticipant(forPhoneNumber: contact)
        // Inviting someone again changes their role instead of adding them twice.
        let existing = share.participants.first { $0.userIdentity.lookupInfo == participant.userIdentity.lookupInfo }
        let invited = existing ?? participant
        invited.permission = .readWrite
        invited.role = role.participantRole
        if existing == nil {
            share.addParticipant(invited)
        }

        let saved = try await save(share, in: location, policy: .ifServerRecordUnchanged)
        guard let url = (saved as? CKShare)?.url ?? share.url else { throw HouseholdError.noShareLink }
        return url
    }

    func remove(_ member: HouseholdMember, from location: HouseholdLocation) async throws {
        guard let share = try await share(in: location),
              let participant = share.participants.first(where: { $0.participantID == member.id })
        else { return }
        share.removeParticipant(participant)
        try await save(share, in: location, policy: .ifServerRecordUnchanged)
    }

    func setRole(_ role: HouseholdRole, of member: HouseholdMember, in location: HouseholdLocation) async throws {
        guard let share = try await share(in: location),
              let participant = share.participants.first(where: { $0.participantID == member.id })
        else { return }
        participant.role = role.participantRole
        try await save(share, in: location, policy: .ifServerRecordUnchanged)
    }

    func accept(_ metadata: CKShare.Metadata) async throws -> HouseholdLocation {
        let share = try await container.accept(metadata)
        return HouseholdLocation(sharedZone: share.recordID.zoneID)
    }

    func leave(_ location: HouseholdLocation) async throws {
        guard location.isShared else { return }
        let (_, results) = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [location.zoneID])
        try results[location.zoneID]?.get()
    }

    // MARK: - Records

    private func database(for location: HouseholdLocation) -> CKDatabase {
        location.isShared ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private func household(in location: HouseholdLocation) async throws -> Household? {
        try await record(Household.recordID(in: location.zoneID), in: location).flatMap(Household.init(record:))
    }

    private func share(in location: HouseholdLocation) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: location.zoneID)
        return try await record(id, in: location) as? CKShare
    }

    /// The record, or `nil` when it or its zone doesn't exist.
    private func record(_ id: CKRecord.ID, in location: HouseholdLocation) async throws -> CKRecord? {
        do {
            return try await database(for: location).record(for: id)
        } catch let error as CKError where [.unknownItem, .zoneNotFound].contains(error.code) {
            return nil
        }
    }

    /// By default every field is saved as written, whatever the server copy holds: households and
    /// favourites each have a single writer. Shares are fetched first and keep CloudKit's conflict check.
    @discardableResult
    private func save(_ record: CKRecord, in location: HouseholdLocation, policy: CKModifyRecordsOperation.RecordSavePolicy = .allKeys) async throws -> CKRecord {
        let (results, _) = try await database(for: location).modifyRecords(
            saving: [record], deleting: [], savePolicy: policy
        )
        return try results[record.recordID]?.get() ?? record
    }
}
