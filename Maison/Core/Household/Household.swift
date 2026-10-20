import CloudKit
import Foundation

/// The household shared through iCloud: which Home Assistant server it uses, never device state.
struct Household: Sendable, Hashable {
    var name: String
    var serverURL: URL
    /// The server's external URL, when Home Assistant has one configured.
    var remoteURL: URL?
}

/// Where the household's records live: a zone in the owner's private database, seen from the
/// shared database by everyone else.
struct HouseholdLocation: Sendable, Hashable, Codable {
    var zoneName: String
    var ownerName: String
    var isShared: Bool

    /// The zone the owner creates in their own private database.
    static let owned = HouseholdLocation(zoneName: "Household", ownerName: CKCurrentUserDefaultName, isShared: false)

    init(zoneName: String, ownerName: String, isShared: Bool) {
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.isShared = isShared
    }

    init(sharedZone zoneID: CKRecordZone.ID) {
        self.init(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, isShared: true)
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }
}

enum HouseholdRole: String, Sendable, Hashable, CaseIterable {
    case owner
    case administrator
    case resident

    /// Owners and administrators can invite and remove people.
    var canManageMembers: Bool { self != .resident }

    init(_ role: CKShare.ParticipantRole) {
        switch role {
        case .owner: self = .owner
        case .administrator: self = .administrator
        default: self = .resident
        }
    }

    /// The share role given to someone invited with this role. Everyone can edit their favourites.
    var participantRole: CKShare.ParticipantRole {
        self == .administrator ? .administrator : .privateUser
    }
}

/// Someone in the household, as listed in Settings.
struct HouseholdMember: Sendable, Hashable, Identifiable {
    let id: String
    let name: String?
    let role: HouseholdRole
    let isPending: Bool
    let isCurrentUser: Bool

    init(id: String, name: String?, role: HouseholdRole, isPending: Bool = false, isCurrentUser: Bool = false) {
        self.id = id
        self.name = name
        self.role = role
        self.isPending = isPending
        self.isCurrentUser = isCurrentUser
    }

    /// Maps the fields of a `CKShare.Participant`, kept apart so it can be tested without iCloud.
    init(
        participantID: String,
        nameComponents: PersonNameComponents?,
        email: String?,
        phoneNumber: String?,
        role: CKShare.ParticipantRole,
        acceptance: CKShare.ParticipantAcceptanceStatus,
        isCurrentUser: Bool
    ) {
        let formattedName: String? = nameComponents
            .map { $0.formatted(.name(style: .medium)) }
            .flatMap { name -> String? in name.isEmpty ? nil : name }
        self.init(
            id: participantID,
            name: formattedName ?? email ?? phoneNumber,
            role: HouseholdRole(role),
            isPending: acceptance == .pending,
            isCurrentUser: isCurrentUser
        )
    }

    init(_ participant: CKShare.Participant, isCurrentUser: Bool) {
        let identity = participant.userIdentity
        self.init(
            participantID: participant.participantID,
            nameComponents: identity.nameComponents,
            email: identity.lookupInfo?.emailAddress,
            phoneNumber: identity.lookupInfo?.phoneNumber,
            role: participant.role,
            acceptance: participant.acceptanceStatus,
            isCurrentUser: isCurrentUser
        )
    }
}

extension [HouseholdMember] {
    /// The owner first, then administrators, then residents; people who haven't accepted yet last.
    func sortedForDisplay() -> [HouseholdMember] {
        let order: [HouseholdRole] = [.owner, .administrator, .resident]
        return sorted { lhs, rhs in
            if lhs.isPending != rhs.isPending { return !lhs.isPending }
            if lhs.role != rhs.role {
                return order.firstIndex(of: lhs.role)! < order.firstIndex(of: rhs.role)!
            }
            return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
        }
    }
}

// MARK: - Records

extension Household {
    static let recordType = "Household"
    static let recordName = "household"

    private enum Field {
        static let name = "name"
        static let serverURL = "serverURL"
        static let remoteURL = "remoteURL"
    }

    static func recordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    init?(record: CKRecord) {
        guard record.recordType == Self.recordType,
              let name = record[Field.name] as? String,
              let server = (record[Field.serverURL] as? String).flatMap(URL.init(string:)),
              server.host() != nil
        else { return nil }
        self.init(
            name: name,
            serverURL: server,
            remoteURL: (record[Field.remoteURL] as? String).flatMap(URL.init(string:))
        )
    }

    /// Writes the fields into `record`, or into a new record in `zoneID`.
    func record(updating record: CKRecord? = nil, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = record ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID(in: zoneID))
        record[Field.name] = name
        record[Field.serverURL] = serverURL.absoluteString
        record[Field.remoteURL] = remoteURL?.absoluteString
        return record
    }
}

/// One member's favourite devices. Each member writes only their own record.
enum MemberFavorites {
    static let recordType = "MemberFavorites"

    private enum Field {
        static let memberID = "memberID"
        static let entityIDs = "entityIDs"
    }

    static func recordID(for memberID: String, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "favorites-\(memberID)", zoneID: zoneID)
    }

    static func entityIDs(from record: CKRecord) -> [String]? {
        guard record.recordType == recordType else { return nil }
        return record[Field.entityIDs] as? [String] ?? []
    }

    /// An empty list is stored as no value: CloudKit can't infer a field type from an empty array.
    static func record(_ entityIDs: [String], for memberID: String, updating record: CKRecord? = nil, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = record ?? CKRecord(recordType: recordType, recordID: recordID(for: memberID, in: zoneID))
        record[Field.memberID] = memberID
        record[Field.entityIDs] = entityIDs.isEmpty ? nil : entityIDs
        return record
    }
}
