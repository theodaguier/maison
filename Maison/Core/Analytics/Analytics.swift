import Foundation

/// Sends usage events. Screens talk to this type, not to PostHog, so tests can pass a stub.
/// With no project token, or when Share Usage Data is off, every call does nothing.
final class Analytics: @unchecked Sendable {
    static let enabledKey = "analyticsEnabled"
    static let shared = Analytics.live()

    private let client: any AnalyticsClient
    private let defaults: UserDefaults

    init(client: any AnalyticsClient, defaults: UserDefaults) {
        self.client = client
        self.defaults = defaults
    }

    /// On until the person turns it off. A missing value is on, which is what TestFlight ships with.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        client.setEnabled(enabled)
    }

    func track(_ event: AnalyticsEvent) {
        client.start(enabled: isEnabled)
        guard isEnabled, client.isConfigured else { return }
        client.capture(name: event.name, properties: event.properties)
    }

    private static func live() -> Analytics {
        let raw = Bundle.main.object(forInfoDictionaryKey: AnalyticsKey.infoDictionaryKey) as? String
        let client: any AnalyticsClient
        if let key = AnalyticsKey.usable(raw) {
            client = PostHogAnalyticsClient(projectToken: key)
        } else {
            client = InactiveAnalyticsClient()
        }
        return Analytics(client: client, defaults: .standard)
    }
}

protocol AnalyticsClient: Sendable {
    /// False when there is no project token. Capture is then a no-op.
    var isConfigured: Bool { get }
    func start(enabled: Bool)
    func setEnabled(_ enabled: Bool)
    func capture(name: String, properties: [String: String])
}

struct InactiveAnalyticsClient: AnalyticsClient {
    let isConfigured = false
    func start(enabled: Bool) {}
    func setEnabled(_ enabled: Bool) {}
    func capture(name: String, properties: [String: String]) {}
}
