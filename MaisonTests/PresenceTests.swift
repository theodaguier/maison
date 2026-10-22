import Foundation
@testable import Maison
import Testing

struct WebhookTests {
    let local = URL(string: "http://homeassistant.local:8123")!
    let remote = URL(string: "https://maison.example.com")!

    @Test func postsToTheCurrentAddressesThenHomeAssistantCloud() {
        let old = URL(string: "http://192.168.1.10:8123")!
        let cloudhook = URL(string: "https://hooks.nabu.casa/abc")!
        let webhook = Webhook(id: "abc", localURL: old, remoteURL: nil, cloudhookURL: cloudhook)

        #expect(webhook.endpoints(addresses: [local, remote]) == [
            URL(string: "http://homeassistant.local:8123/api/webhook/abc")!,
            URL(string: "https://maison.example.com/api/webhook/abc")!,
            cloudhook,
        ])
    }

    @Test func keepsTheRegistrationAddressesWithoutASignIn() {
        let webhook = Webhook(id: "abc", localURL: local, remoteURL: remote)
        #expect(webhook.endpoints(addresses: nil) == [
            URL(string: "http://homeassistant.local:8123/api/webhook/abc")!,
            URL(string: "https://maison.example.com/api/webhook/abc")!,
        ])
    }
}

@MainActor
struct PresenceReporterTests {
    let defaults = UserDefaults(suiteName: "PresenceReporterTests.\(UUID().uuidString)")!
    let webhook = Webhook(id: "abc", localURL: URL(string: "http://homeassistant.local:8123"), remoteURL: nil)

    @Test func forgettingStopsReportingAndDropsTheWebhook() {
        defaults.set(true, forKey: "presenceEnabled")
        let storage = MemoryWebhookStorage(webhook)
        let presence = PresenceReporter(webhooks: storage, defaults: defaults)
        #expect(presence.isEnabled)

        presence.forget()

        #expect(!presence.isEnabled)
        #expect(!defaults.bool(forKey: "presenceEnabled"))
        #expect(storage.load() == nil)
    }

    @Test func signingOutForgetsThePresence() async {
        defaults.set(true, forKey: "presenceEnabled")
        let storage = MemoryWebhookStorage(webhook)
        let presence = PresenceReporter(webhooks: storage, defaults: defaults)
        let store = HomeStore(
            credentialStore: MemoryCredentialStorage(),
            defaults: defaults,
            household: HouseholdStore(cloud: nil, defaults: defaults),
            presence: presence
        )

        await store.signOut()

        #expect(!presence.isEnabled)
        #expect(storage.load() == nil)
    }

    @Test func theDemoNeitherRegistersNorRemembers() async throws {
        let storage = MemoryWebhookStorage()
        let presence = PresenceReporter(webhooks: storage, defaults: defaults, isDemo: true)

        try await presence.enable(with: DemoHome.store())

        #expect(presence.isEnabled)
        #expect(storage.load() == nil)
        #expect(!defaults.bool(forKey: "presenceEnabled"))
    }

    @Test func dropsTheDemoWebhookEarlierBuildsSaved() {
        defaults.set(true, forKey: "presenceEnabled")
        let storage = MemoryWebhookStorage(Webhook(id: "demo", localURL: nil, remoteURL: nil))

        let presence = PresenceReporter(webhooks: storage, defaults: defaults)

        #expect(storage.load() == nil)
        #expect(!presence.isEnabled)
    }
}

@MainActor
struct FreshCredentialsTests {
    let server = URL(string: "http://homeassistant.local:8123")!

    @Test func refreshesAnExpiredTokenBeforeARESTCall() async throws {
        let keychain = MemoryCredentialStorage()
        try keychain.save(Credentials(serverURL: server, accessToken: "old", refreshToken: "refresh", expiresAt: .distantPast))
        let refreshes = Log<URL>()
        let connector = ServerConnector(refresh: { credentials, address in
            refreshes.append(address)
            var refreshed = credentials
            refreshed.accessToken = "new"
            refreshed.expiresAt = .distantFuture
            return refreshed
        })
        let defaults = UserDefaults(suiteName: "FreshCredentialsTests.\(UUID().uuidString)")!
        let store = HomeStore(
            credentialStore: keychain, defaults: defaults,
            household: HouseholdStore(cloud: nil, defaults: defaults),
            presence: PresenceReporter(webhooks: MemoryWebhookStorage(), defaults: defaults),
            connector: connector
        )

        let editor = try #require(try await store.configEditor())
        #expect(editor.accessToken == "new")
        // Still valid: no second refresh.
        _ = try await store.freshCredentials()
        #expect(refreshes.values == [server])
        #expect(try keychain.load()?.accessToken == "new")
    }
}
