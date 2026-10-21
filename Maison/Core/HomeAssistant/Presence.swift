import CoreLocation
import Foundation
import Security
import UIKit

/// Lets Home Assistant know when this iPhone leaves or comes home, so rules like "When everyone leaves" work.
///
/// Maison registers itself with the server as a "mobile app" device (as Home Assistant's own app does),
/// then sends the position on significant location changes only — a few times a day, kind to the battery.
@MainActor
@Observable
final class PresenceReporter: NSObject, CLLocationManagerDelegate {
    static let shared = PresenceReporter()

    private(set) var authorization: CLAuthorizationStatus
    private(set) var isEnabled: Bool
    /// The sample home's reporter: the switch works, nothing is asked or sent.
    let isDemo: Bool

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private nonisolated let webhooks: any WebhookStorage
    /// Read on every position, so it goes to the server's current addresses.
    private nonisolated let credentialStore: any CredentialStorage

    private static let enabledKey = "presenceEnabled"

    init(
        webhooks: any WebhookStorage = KeychainWebhookStorage(),
        credentialStore: any CredentialStorage = CredentialStore(),
        defaults: UserDefaults = .standard,
        isDemo: Bool = false
    ) {
        self.webhooks = webhooks
        self.credentialStore = credentialStore
        self.defaults = defaults
        self.isDemo = isDemo
        isEnabled = !isDemo && defaults.bool(forKey: Self.enabledKey)
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Earlier builds saved the demo's fake webhook, which then kept the real registration from ever happening.
        if !isDemo, webhooks.load()?.isDemo == true {
            webhooks.delete()
            setEnabled(false)
        }
    }

    /// Called at launch: iOS relaunches the app in the background for location changes.
    func resume() {
        guard isEnabled, webhooks.load() != nil else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    /// Asks for the location permission, registers with Home Assistant and attaches the iPhone to the person.
    func enable(with store: HomeStore) async throws {
        guard !isDemo else {
            isEnabled = true
            return
        }
        if authorization == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestAlwaysAuthorization()
            }
        }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(authorization) else { throw PresenceError.denied }
        if webhooks.load() == nil {
            webhooks.save(try await store.registerMobileApp(deviceName: UIDevice.current.name))
        }
        setEnabled(true)
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
        // The tracker appears once the first position arrives.
        try? await Task.sleep(for: .seconds(3))
        if let webhook = webhooks.load() { try? await store.attachTracker(webhookID: webhook.id) }
    }

    func disable() {
        setEnabled(false)
        if !isDemo { manager.stopMonitoringSignificantLocationChanges() }
    }

    /// Stops reporting and drops the webhook, on signing out: it belongs to the server left.
    func forget() {
        disable()
        webhooks.delete()
    }

    private func setEnabled(_ isOn: Bool) {
        isEnabled = isOn
        if !isDemo { defaults.set(isOn, forKey: Self.enabledKey) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            guard status != .notDetermined else { return }
            self.authorizationWaiters.forEach { $0.resume() }
            self.authorizationWaiters.removeAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let webhook = webhooks.load() else { return }
        let endpoints = webhook.endpoints(addresses: (try? credentialStore.load())?.addresses)
        let body: [String: Any] = [
            "type": "update_location",
            "data": [
                "gps": [location.coordinate.latitude, location.coordinate.longitude],
                "gps_accuracy": max(location.horizontalAccuracy, 1),
                "altitude": location.altitude,
            ],
        ]
        Task.detached {
            // At home the local address answers at once; away, it gives up quickly for the remote one.
            for (index, endpoint) in endpoints.enumerated() {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = index == 0 && endpoints.count > 1 ? 5 : 15
                if let (_, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true {
                    return
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    enum PresenceError: LocalizedError {
        case denied

        var errorDescription: String? {
            String(localized: "Maison can’t use the location. Allow it in Settings › Maison › Location.")
        }
    }
}

/// The webhook Home Assistant gave Maison, kept in the keychain: whoever has it can post positions.
struct Webhook: Codable, Sendable, Equatable {
    let id: String
    /// The server's addresses at registration, used when the sign-in is gone.
    let localURL: URL?
    let remoteURL: URL?
    /// Home Assistant Cloud's address for this webhook, which works from anywhere.
    var cloudhookURL: URL? = nil

    /// What earlier builds saved when presence was turned on in the demo.
    var isDemo: Bool { id == "demo" && localURL == nil && remoteURL == nil }

    /// Where to post, local first. `addresses` are the server's current ones, which may have changed since registration.
    func endpoints(addresses: [URL]?) -> [URL] {
        let servers = addresses ?? [localURL, remoteURL].compactMap { $0 }
        let all = servers.map { $0.appending(path: "api/webhook/\(id)") } + [cloudhookURL].compactMap { $0 }
        return all.reduce(into: []) { endpoints, url in
            if !endpoints.contains(url) { endpoints.append(url) }
        }
    }
}

/// Where the webhook is kept.
protocol WebhookStorage: Sendable {
    func load() -> Webhook?
    func save(_ webhook: Webhook)
    func delete()
}

/// The keychain, readable after the first unlock so background location updates can post.
struct KeychainWebhookStorage: WebhookStorage {
    private let service = "com.theodaguier.maison.webhook"

    func load() -> Webhook? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Webhook.self, from: data)
    }

    func save(_ webhook: Webhook) {
        delete()
        guard let data = try? JSONEncoder().encode(webhook) else { return }
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                         kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// Memory only: for the demo, which never registers, and for tests.
final class MemoryWebhookStorage: WebhookStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var webhook: Webhook?

    init(_ webhook: Webhook? = nil) {
        self.webhook = webhook
    }

    func load() -> Webhook? { lock.withLock { webhook } }
    func save(_ webhook: Webhook) { lock.withLock { self.webhook = webhook } }
    func delete() { lock.withLock { webhook = nil } }
}
