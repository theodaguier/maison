import CloudKit
import Foundation
import Observation

/// The household shared through iCloud and the current member's favourites.
///
/// Favourites are kept in `UserDefaults` too, so they work without iCloud and show at once on launch;
/// iCloud wins whenever it has a copy.
@MainActor
@Observable
final class HouseholdStore {
    enum Status: Equatable {
        case loading
        /// No iCloud account on this device: favourites stay on the device and sharing is off.
        case unavailable
        case ready
        case failed(String)
    }

    private(set) var status: Status = .loading
    private(set) var household: Household?
    private(set) var location: HouseholdLocation?
    private(set) var members: [HouseholdMember] = []
    private(set) var favoriteIDs: [String]
    /// An invitation opened but not accepted yet: the app asks first.
    var pendingInvitation: CKShare.Metadata?
    /// Set once an invitation is accepted, to welcome the person on the home screen.
    var joinedHouseholdName: String?
    /// The scanned plan; kept on the device too, so it shows without iCloud.
    private(set) var floorPlan: FloorPlan?

    @ObservationIgnored private let cloud: (any HouseholdCloud)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var memberID: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Favourites changed before iCloud loaded: the device copy is newer than iCloud's.
    @ObservationIgnored private var hasUnsyncedFavorites = false

    /// Pass `nil` for `cloud` to keep everything on the device.
    init(cloud: (any HouseholdCloud)?, defaults: UserDefaults = .standard) {
        self.cloud = cloud
        self.defaults = defaults
        favoriteIDs = defaults.stringArray(forKey: Self.favoritesKey) ?? []
        floorPlan = defaults.data(forKey: Self.planKey).flatMap { try? JSONDecoder().decode(FloorPlan.self, from: $0) }
        if cloud == nil {
            status = .unavailable
        }
    }

    /// A household filled with sample members, for previews and the `-demo` launch argument.
    init(demo household: Household, members: [HouseholdMember], plan: FloorPlan? = nil) {
        cloud = nil
        defaults = UserDefaults(suiteName: "demo") ?? .standard
        favoriteIDs = []
        floorPlan = plan
        self.household = household
        self.members = members
        location = .owned
        status = .ready
    }

    private static let favoritesKey = "favoriteEntityIDs"
    private static let planKey = "floorPlan"
    /// The name the current user chose. Kept on the device so it survives the participant id
    /// changing when the household is shared for the first time, and published to iCloud for everyone else.
    private static let displayNameKey = "householdDisplayName"

    /// The role of the person using the app.
    var currentRole: HouseholdRole {
        members.first(where: \.isCurrentUser)?.role ?? (location?.isShared == true ? .resident : .owner)
    }

    var canInvite: Bool {
        status == .ready && household != nil && currentRole.canManageMembers
    }

    // MARK: - Loading

    /// Loads the household once; later calls wait for the first load.
    func start() async {
        let task = loadTask ?? Task { await load() }
        loadTask = task
        await task.value
    }

    func reload() async {
        loadTask = Task { await load() }
        await loadTask?.value
    }

    private func load() async {
        guard let cloud else { return }
        do {
            guard let memberID = try await cloud.currentUserID() else {
                status = .unavailable
                return
            }
            self.memberID = memberID
            if let stored = try await cloud.findHousehold() {
                location = stored.location
                household = stored.household
                try await syncFavorites()
                if let plan = try await cloud.floorPlan(in: stored.location) { keepPlan(plan) }
                try await refreshMembers()
            }
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Called once signed in to Home Assistant: creates the household on first use, or keeps the
    /// owner's copy of the server details up to date.
    func serverConnected(_ server: Household) async {
        await start()
        if case .failed = status {
            await reload()
        }
        guard let cloud, status == .ready else { return }
        do {
            if let location {
                guard !location.isShared, household != server else { return }
                try await cloud.save(server, in: location)
                household = server
            } else {
                location = try await cloud.create(server)
                household = server
                try await syncFavorites()
                try await refreshMembers()
            }
        } catch {
            // The household is retried on the next connection; favourites still work locally.
        }
    }

    /// Joins the household of an invitation the user opened.
    func accept(_ metadata: CKShare.Metadata) async {
        guard let cloud else { return }
        await start()
        do {
            _ = try await cloud.accept(metadata)
            await reload()
            joinedHouseholdName = household?.name ?? metadata.share[CKShare.SystemFieldKey.title] as? String
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Members

    func refreshMembers() async throws {
        guard let cloud, let location else { return }
        var members = try await cloud.members(in: location)
        if members.isEmpty, !location.isShared, let memberID {
            // Never shared yet: the owner is alone, and iCloud has no name for them.
            members = [HouseholdMember(id: memberID, name: nil, role: .owner, isCurrentUser: true)]
        }
        members = members.map(\.normalized)
        let chosen = (try? await cloud.displayNames(of: members.map(\.id), in: location)) ?? [:]
        let localName = HouseholdMember.nonEmpty(defaults.string(forKey: Self.displayNameKey))
        if let localName, let me = members.first(where: \.isCurrentUser), chosen[me.id] != localName {
            try? await cloud.saveDisplayName(localName, of: me.id, in: location)
        }
        members = members.map { member in
            if member.isCurrentUser, let localName { return member.withName(localName) }
            if let name = chosen[member.id] { return member.withName(name) }
            return member
        }
        self.members = members.sortedForDisplay()
    }

    /// Saves the name the current user wants the household to see.
    func setDisplayName(_ name: String, of member: HouseholdMember) async throws {
        guard member.isCurrentUser, let trimmed = HouseholdMember.nonEmpty(name) else { return }
        if let cloud, let location {
            try await cloud.saveDisplayName(trimmed, of: member.id, in: location)
        }
        defaults.set(trimmed, forKey: Self.displayNameKey)
        members = members.map { $0.isCurrentUser ? $0.withName(trimmed) : $0 }
    }

    /// Adds the person to the household, then has `makeAccount` create their account on the home's
    /// server, which signs them in by itself once they join. Inviting someone again reuses theirs.
    /// `makeAccount` takes a name, a username and a password, and returns the account's id.
    /// Returns the link to send to the person invited.
    func invite(
        _ contact: String,
        makeAccount: (_ name: String, _ username: String, _ password: String) async throws -> String
    ) async throws -> URL {
        guard let cloud, let household, let location else { throw HouseholdError.noShareLink }
        let invitation = try await cloud.invite(contact, to: household, in: location)
        try? await refreshMembers()
        if try await cloud.memberAccess(of: invitation.participantID, in: location) == nil {
            let username = MemberAccess.makeUsername()
            let password = MemberAccess.makePassword()
            let accountID = try await makeAccount(invitation.name, username, password)
            try await cloud.saveMemberAccess(
                MemberAccess(participantID: invitation.participantID, accountID: accountID, username: username, password: password),
                in: location
            )
        }
        return invitation.url
    }

    /// Removes the person, and first the account Maison made for them, so they lose the home as well
    /// as the household. `deleteAccount` takes the account's id.
    func remove(_ member: HouseholdMember, deleteAccount: (String) async throws -> Void) async throws {
        guard let cloud, let location else { return }
        let access = try await cloud.memberAccess(of: member.id, in: location)
        if let access {
            try await deleteAccount(access.accountID)
        }
        try await cloud.remove(member, from: location)
        if access != nil {
            try? await cloud.deleteMemberAccess(of: member.id, in: location)
        }
        try? await refreshMembers()
    }

    /// The sign-in made for the current user when they were invited, while it hasn't been used.
    func unusedAccess() async -> MemberAccess? {
        guard let cloud, let location, location.isShared,
              let participantID = try? await cloud.currentParticipantID(in: location),
              let access = try? await cloud.memberAccess(of: participantID, in: location),
              access.password != nil
        else { return nil }
        return access
    }

    /// Clears the password once it got the person in. The account's id stays, to remove them later.
    func accessUsed(_ access: MemberAccess) async {
        guard let cloud, let location else { return }
        var used = access
        used.password = nil
        try? await cloud.saveMemberAccess(used, in: location)
    }

    /// Leaves a household someone else shared. Favourites stay on the device.
    func leave() async throws {
        guard let cloud, let location, location.isShared else { return }
        try await cloud.leave(location)
        self.location = nil
        household = nil
        members = []
    }

    // MARK: - Floor plan

    /// Saves on the device at once, then in iCloud for the rest of the household.
    func saveFloorPlan(_ plan: FloorPlan) async throws {
        keepPlan(plan)
        guard let cloud, let location else { return }
        try await cloud.saveFloorPlan(plan, in: location)
    }

    private func keepPlan(_ plan: FloorPlan) {
        floorPlan = plan
        defaults.set(try? JSONEncoder().encode(plan), forKey: Self.planKey)
    }

    // MARK: - Favourites

    func toggleFavorite(_ entityID: String) {
        if let index = favoriteIDs.firstIndex(of: entityID) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(entityID)
        }
        defaults.set(favoriteIDs, forKey: Self.favoritesKey)
        uploadFavorites()
    }

    /// Replaces the favourites, in this order: the home's shortcuts, edited.
    func setFavorites(_ entityIDs: [String]) {
        var seen = Set<String>()
        favoriteIDs = entityIDs.filter { seen.insert($0).inserted }
        defaults.set(favoriteIDs, forKey: Self.favoritesKey)
        uploadFavorites()
    }

    /// Takes the iCloud copy when there is one, otherwise uploads the favourites kept on the device.
    private func syncFavorites() async throws {
        guard let cloud, let location, let memberID else { return }
        if hasUnsyncedFavorites {
            try await cloud.saveFavorites(favoriteIDs, of: memberID, in: location)
            hasUnsyncedFavorites = false
        } else if let saved = try await cloud.favorites(of: memberID, in: location) {
            favoriteIDs = saved
            defaults.set(saved, forKey: Self.favoritesKey)
        } else if !favoriteIDs.isEmpty {
            try await cloud.saveFavorites(favoriteIDs, of: memberID, in: location)
        }
    }

    /// Saves in order, so quick toggles can't land out of sequence.
    private func uploadFavorites() {
        guard let cloud else { return }
        guard let location, let memberID else {
            hasUnsyncedFavorites = true
            return
        }
        let entityIDs = favoriteIDs
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            try? await cloud.saveFavorites(entityIDs, of: memberID, in: location)
        }
    }

    /// Waits for pending favourite uploads; used by tests.
    func waitForUploads() async {
        await saveTask?.value
    }
}
