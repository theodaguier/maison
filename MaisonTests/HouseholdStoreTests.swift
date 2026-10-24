import Foundation
@testable import Maison
import Testing

@MainActor
struct HouseholdStoreTests {
    let defaults = UserDefaults(suiteName: "HouseholdStoreTests-\(UUID().uuidString)")!
    let server = Household(name: "Maison", serverURL: URL(string: "http://192.168.1.179:8123")!)

    @Test func withoutICloudFavoritesStayOnTheDevice() async {
        let store = HouseholdStore(cloud: FakeHouseholdCloud(userID: nil), defaults: defaults)
        await store.start()
        store.toggleFavorite("light.salon")

        #expect(store.status == .unavailable)
        #expect(!store.canInvite)
        #expect(defaults.stringArray(forKey: "favoriteEntityIDs") == ["light.salon"])
        #expect(HouseholdStore(cloud: nil, defaults: defaults).favoriteIDs == ["light.salon"])
    }

    @Test func firstConnectionCreatesTheHouseholdAndUploadsLocalFavorites() async {
        defaults.set(["light.salon"], forKey: "favoriteEntityIDs")
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)

        await store.serverConnected(server)

        #expect(await cloud.createdCount == 1)
        #expect(store.household == server)
        #expect(store.location == .owned)
        #expect(await cloud.storedFavorites(of: "_me", in: .owned) == ["light.salon"])
        #expect(store.members.map(\.role) == [.owner])
        #expect(store.members.first?.isCurrentUser == true)
        #expect(store.canInvite)
    }

    @Test func iCloudFavoritesReplaceTheDeviceCopy() async {
        defaults.set(["light.old"], forKey: "favoriteEntityIDs")
        let cloud = FakeHouseholdCloud()
        _ = try? await cloud.create(server)
        await cloud.setFavorites(["lock.porte", "light.salon"], of: "_me", in: .owned)
        let store = HouseholdStore(cloud: cloud, defaults: defaults)

        await store.start()

        #expect(store.favoriteIDs == ["lock.porte", "light.salon"])
        #expect(defaults.stringArray(forKey: "favoriteEntityIDs") == ["lock.porte", "light.salon"])
    }

    @Test func togglingAFavoriteSavesItToICloud() async {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)

        store.toggleFavorite("light.salon")
        store.toggleFavorite("lock.porte")
        store.toggleFavorite("light.salon")
        await store.waitForUploads()

        #expect(store.favoriteIDs == ["lock.porte"])
        #expect(await cloud.storedFavorites(of: "_me", in: .owned) == ["lock.porte"])
    }

    @Test func aFavoriteToggledBeforeLoadingWinsOverICloud() async {
        let cloud = FakeHouseholdCloud()
        _ = try? await cloud.create(server)
        await cloud.setFavorites(["light.salon"], of: "_me", in: .owned)
        let store = HouseholdStore(cloud: cloud, defaults: defaults)

        store.toggleFavorite("lock.porte")
        await store.start()

        #expect(store.favoriteIDs == ["lock.porte"])
        #expect(await cloud.storedFavorites(of: "_me", in: .owned) == ["lock.porte"])
    }

    @Test func aJoinedHouseholdPrefillsTheServer() async {
        let cloud = FakeHouseholdCloud()
        let location = await cloud.addSharedHousehold(server, members: [
            HouseholdMember(id: "owner", name: "Théo", role: .owner),
            HouseholdMember(id: "me", name: "Camille", role: .resident, isCurrentUser: true),
        ])
        let store = HouseholdStore(cloud: cloud, defaults: defaults)

        await store.reload()

        #expect(store.location == location)
        #expect(store.household?.serverURL == server.serverURL)
        #expect(store.currentRole == .resident)
        #expect(!store.canInvite)
        #expect(store.members.map(\.name) == ["Théo", "Camille"])
    }

    @Test func membersOfAJoinedHouseholdNeverRewriteIt() async {
        let cloud = FakeHouseholdCloud()
        _ = await cloud.addSharedHousehold(server, members: [HouseholdMember(id: "me", name: "Camille", role: .administrator, isCurrentUser: true)])
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        var otherAddress = server
        otherAddress.serverURL = URL(string: "http://homeassistant.local:8123")!

        await store.serverConnected(otherAddress)

        #expect(await cloud.createdCount == 0)
        #expect(await cloud.savedHouseholds.isEmpty)
        #expect(store.household == server)
        #expect(store.canInvite)
    }

    @Test func theOwnerKeepsTheServerDetailsUpToDate() async {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)
        var renamed = server
        renamed.name = "Chez nous"

        await store.serverConnected(server)
        await store.serverConnected(renamed)

        #expect(await cloud.savedHouseholds == [renamed])
        #expect(store.household == renamed)
    }

    @Test func invitingAddsAPendingMember() async throws {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)

        let link = try await store.invite("camille@icloud.com", as: .administrator)

        #expect(link.host() == "www.icloud.com")
        #expect(await cloud.invitations.map(\.role) == [.administrator])
        #expect(store.members.last?.name == "camille@icloud.com")
        #expect(store.members.last?.isPending == true)
    }

    @Test func leavingForgetsTheHouseholdButKeepsFavorites() async throws {
        let cloud = FakeHouseholdCloud()
        let location = await cloud.addSharedHousehold(server, members: [])
        await cloud.setFavorites(["light.salon"], of: "_me", in: location)
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.start()

        try await store.leave()

        #expect(store.household == nil)
        #expect(store.members.isEmpty)
        #expect(store.favoriteIDs == ["light.salon"])
    }

    @Test func theCurrentUserIsNeverLeftAsAPendingInvitation() async throws {
        let cloud = FakeHouseholdCloud()
        _ = try await cloud.create(server)
        await cloud.setMembers([
            HouseholdMember(id: "_me", name: nil, role: .owner, isPending: true, isCurrentUser: true),
            HouseholdMember(id: "jules", name: "jules@icloud.com", role: .resident, isPending: true, contact: "jules@icloud.com"),
        ], in: .owned)
        let store = HouseholdStore(cloud: cloud, defaults: defaults)

        await store.start()

        let me = try #require(store.members.first { $0.isCurrentUser })
        #expect(!me.isPending)
        #expect(!me.showsAsInvitation)
        #expect(me.resolvedName(accountName: "Théo") == "Théo")
        #expect(me.initials(accountName: "Théo") == "T")
        #expect(store.members.last?.showsAsInvitation == true)
        #expect(store.members.last?.invitationContact == "jules@icloud.com")
    }

    @Test func aChosenDisplayNameFillsTheMissingAppleIDName() async throws {
        let cloud = FakeHouseholdCloud()
        let store = HouseholdStore(cloud: cloud, defaults: defaults)
        await store.serverConnected(server)
        let me = try #require(store.members.first { $0.isCurrentUser })

        try await store.setDisplayName("  Théo  ", of: me)
        #expect(store.members.first?.name == "Théo")

        await store.reload()

        #expect(store.members.first?.name == "Théo")
        #expect(store.members.first?.showsAsInvitation == false)
        let names = try await cloud.displayNames(of: ["_me"], in: .owned)
        #expect(names["_me"] == "Théo")
    }
}
