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

    /// Off until the person turns it on: an identifier stored on the device needs their consent.
    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        client.setEnabled(enabled)
    }

    /// The SDK is only set up once sharing is on, so a person who never opts in never reaches PostHog.
    func track(_ event: AnalyticsEvent) {
        guard isEnabled, client.isConfigured else { return }
        client.start(enabled: true)
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
