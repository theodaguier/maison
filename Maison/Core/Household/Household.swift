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

    /// Owners and administrators can invite and remove people. Residents only come from households
    /// shared before everyone was invited as an administrator.
    var canManageMembers: Bool { self != .resident }

    init(_ role: CKShare.ParticipantRole) {
        switch role {
        case .owner: self = .owner
        case .administrator: self = .administrator
        default: self = .resident
        }
    }
}

/// Someone in the household, as listed in Settings.
struct HouseholdMember: Sendable, Hashable, Identifiable {
    let id: String
    let name: String?
    let role: HouseholdRole
    let isPending: Bool
    let isCurrentUser: Bool
    /// Email or phone the invitation was addressed to, when iCloud still has it.
    let contact: String?

    init(id: String, name: String?, role: HouseholdRole, isPending: Bool = false, isCurrentUser: Bool = false, contact: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.isPending = isPending
        self.isCurrentUser = isCurrentUser
        self.contact = contact
    }

    /// Maps the fields of a `CKShare.Participant`, kept apart so it can be tested without iCloud.
    ///
    /// CloudKit reports the share owner, and often the current user, as `.pending` or `.unknown`,
    /// and on iOS 26 the owner's name is nil unless the extended share-access entitlement is set.
    /// Neither person was invited: the owner created the share, and the current user is already in
    /// it. Only someone else whose status is exactly `.pending` is an invitation.
    init(
        participantID: String,
        nameComponents: PersonNameComponents?,
        email: String?,
        phoneNumber: String?,
        role: CKShare.ParticipantRole,
        acceptance: CKShare.ParticipantAcceptanceStatus,
        isCurrentUser: Bool
    ) {
        let formattedName = nameComponents
            .map { $0.formatted(.name(style: .medium)) }
            .flatMap { Self.nonEmpty($0) }
        let contact = Self.nonEmpty(email ?? phoneNumber)
        self.init(
            id: participantID,
            name: formattedName ?? contact,
            role: HouseholdRole(role),
            isPending: Self.isPendingInvitation(role: role, acceptance: acceptance, isCurrentUser: isCurrentUser),
            isCurrentUser: isCurrentUser,
            contact: contact
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

    /// Whether this participant is an invitation that hasn't been accepted.
    static func isPendingInvitation(
        role: CKShare.ParticipantRole,
        acceptance: CKShare.ParticipantAcceptanceStatus,
        isCurrentUser: Bool
    ) -> Bool {
        if isCurrentUser || role == .owner { return false }
        return acceptance == .pending
    }

    /// A removed participant is gone. The owner and the current user stay listed: CloudKit's
    /// acceptance status for them is not a reliable "removed".
    static func belongsInHousehold(
        role: CKShare.ParticipantRole,
        acceptance: CKShare.ParticipantAcceptanceStatus,
        isCurrentUser: Bool
    ) -> Bool {
        if isCurrentUser || role == .owner { return true }
        return acceptance != .removed
    }

    /// Whether this share participant is the person using the app.
    ///
    /// `currentUserParticipant` is sometimes missing on the owner's private database, and on iOS 26
    /// the owner's user record id is nil without the extended share-access entitlement. The owner
    /// of a household kept in this iPhone's private database is that person.
    static func matchesCurrentUser(
        role: CKShare.ParticipantRole,
        participantRecordName: String?,
        currentUserRecordName: String?,
        matchesCurrentParticipant: Bool,
        inPrivateDatabase: Bool
    ) -> Bool {
        if matchesCurrentParticipant { return true }
        if let currentUserRecordName, participantRecordName == currentUserRecordName { return true }
        return inPrivateDatabase && role == .owner
    }

    /// The stored pending flag, corrected when the owner or the current user was marked invited.
    var normalized: HouseholdMember {
        guard isPending, isCurrentUser || role == .owner else { return self }
        return HouseholdMember(id: id, name: name, role: role, isPending: false, isCurrentUser: isCurrentUser, contact: contact)
    }

    /// Whether Settings should present this person as an invitation. The owner and the current user never are.
    var showsAsInvitation: Bool {
        normalized.isPending
    }

    func withName(_ name: String?) -> HouseholdMember {
        HouseholdMember(id: id, name: name, role: role, isPending: isPending, isCurrentUser: isCurrentUser, contact: contact)
    }

    /// The name to show. A name from iCloud wins. The current user, whose Apple ID name is often
    /// missing, falls back to `accountName` — the name already known on this iPhone. That fallback
    /// never applies to someone else, and a missing name is never the "invitation sent" label.
    func resolvedName(accountName: String?) -> String? {
        if let name = Self.nonEmpty(name) { return name }
        guard isCurrentUser, !showsAsInvitation else { return nil }
        return Self.nonEmpty(accountName)
    }

    /// One or two initials. `nil` when there is no name to draw from: the avatar uses a symbol then, never "?".
    func initials(accountName: String?) -> String? {
        guard let name = resolvedName(accountName: accountName) else { return nil }
        let visible = name.split(separator: "@", maxSplits: 1).first.map(String.init) ?? name
        let words = visible.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = Self.mark(in: words[0]), let last = Self.mark(in: words[words.count - 1]) {
            return String([first, last]).uppercased()
        }
        guard let mark = Self.mark(in: visible) else { return nil }
        return String(mark).uppercased()
    }

    /// The address a pending invitation can be sent to again.
    var invitationContact: String? {
        if let contact = Self.nonEmpty(contact) { return contact }
        guard let name = Self.nonEmpty(name), name.contains("@") || name.first == "+" else { return nil }
        return name
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mark(in text: some StringProtocol) -> Character? {
        text.first { $0.isLetter || $0.isNumber }
    }
}

extension [HouseholdMember] {
    /// The owner first, then administrators, then residents; people who haven't accepted yet last.
    func sortedForDisplay() -> [HouseholdMember] {
        let order: [HouseholdRole] = [.owner, .administrator, .resident]
        return sorted { lhs, rhs in
            if lhs.showsAsInvitation != rhs.showsAsInvitation { return !lhs.showsAsInvitation }
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

/// The name a member chose to show. This is what they typed, never a copy of their Apple ID identity:
/// iOS 26 only allows that identity to be displayed, not stored.
enum MemberProfile {
    static let recordType = "MemberProfile"

    private enum Field {
        static let displayName = "displayName"
    }

    static func recordID(for memberID: String, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile-\(memberID)", zoneID: zoneID)
    }

    static func displayName(from record: CKRecord) -> String? {
        guard record.recordType == recordType else { return nil }
        return HouseholdMember.nonEmpty(record[Field.displayName] as? String)
    }

    static func record(_ displayName: String, for memberID: String, updating record: CKRecord? = nil, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = record ?? CKRecord(recordType: recordType, recordID: recordID(for: memberID, in: zoneID))
        record[Field.displayName] = HouseholdMember.nonEmpty(displayName)
        return record
    }
}

/// The account on the home's server that Maison made for someone it invited, so they're signed in
/// without typing anything. The password is used once, then replaced on the server and cleared here.
struct MemberAccess: Sendable, Hashable {
    /// The share participant it was made for: only that person reads it.
    let participantID: String
    /// The server's id for the account, so it goes when the person is removed from the household.
    let accountID: String
    let username: String
    var password: String?
}

/// `MemberAccess` in the household's zone. The password is end-to-end encrypted, never a plain field.
extension MemberAccess {
    static let recordType = "MemberAccess"

    private enum Field {
        static let participantID = "participantID"
        static let accountID = "accountID"
        static let username = "username"
        static let password = "password"
    }

    static func recordID(for participantID: String, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "access-\(participantID)", zoneID: zoneID)
    }

    init?(record: CKRecord) {
        guard record.recordType == Self.recordType,
              let participantID = record[Field.participantID] as? String,
              let accountID = record[Field.accountID] as? String,
              let username = record[Field.username] as? String
        else { return nil }
        self.init(
            participantID: participantID,
            accountID: accountID,
            username: username,
            password: HouseholdMember.nonEmpty(record.encryptedValues[Field.password] as? String)
        )
    }

    func record(updating record: CKRecord? = nil, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = record ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: participantID, in: zoneID))
        record[Field.participantID] = participantID
        record[Field.accountID] = accountID
        record[Field.username] = username
        record.encryptedValues[Field.password] = password
        return record
    }
}
