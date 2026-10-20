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
    private(set) var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []

    private static let enabledKey = "presenceEnabled"

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// Called at launch: iOS relaunches the app in the background for location changes.
    func resume() {
        guard isEnabled, Webhook.load() != nil else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    /// Asks for the location permission, registers with Home Assistant and attaches the iPhone to the person.
    func enable(with store: HomeStore) async throws {
        if authorization == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestAlwaysAuthorization()
            }
        }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(authorization) else { throw PresenceError.denied }
        if Webhook.load() == nil {
            Webhook.save(try await store.registerMobileApp(deviceName: UIDevice.current.name))
        }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
        // The tracker appears once the first position arrives.
        try? await Task.sleep(for: .seconds(3))
        if let webhook = Webhook.load() { try? await store.attachTracker(webhookID: webhook.id) }
    }

    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        manager.stopMonitoringSignificantLocationChanges()
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
        guard let location = locations.last, let webhook = Webhook.load() else { return }
        let body: [String: Any] = [
            "type": "update_location",
            "data": [
                "gps": [location.coordinate.latitude, location.coordinate.longitude],
                "gps_accuracy": max(location.horizontalAccuracy, 1),
                "altitude": location.altitude,
            ],
        ]
        Task.detached {
            // At home the local address answers; away, the remote one.
            for server in [webhook.remoteURL, webhook.localURL].compactMap({ $0 }) {
                var request = URLRequest(url: server.appending(path: "api/webhook/\(webhook.id)"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 15
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
struct Webhook: Codable, Sendable {
    let id: String
    let localURL: URL?
    let remoteURL: URL?

    private static let service = "com.theodaguier.maison.webhook"

    static func load() -> Webhook? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Webhook.self, from: data)
    }

    static func save(_ webhook: Webhook) {
        delete()
        guard let data = try? JSONEncoder().encode(webhook) else { return }
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                         kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
