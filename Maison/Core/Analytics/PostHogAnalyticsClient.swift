import Foundation
@preconcurrency import PostHog

/// PostHog, pinned to the EU ingestion host, with an anonymous id and no autocapture.
/// The SDK dropped IDFA in 1.2.0; this app does not link AdSupport or ask to track.
final class PostHogAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    /// EU cloud only. Not read from configuration, so a build setting cannot point the app at another region.
    static let host = "https://eu.i.posthog.com"

    private let projectToken: String
    private let lock = NSLock()
    private var didStart = false
    private var appliedEnabled: Bool?

    let isConfigured = true

    init(projectToken: String) {
        self.projectToken = projectToken
    }

    func start(enabled: Bool) {
        lock.lock()
        let needsSetup = !didStart
        if needsSetup { didStart = true }
        let needsApply = appliedEnabled != enabled
        if needsApply { appliedEnabled = enabled }
        lock.unlock()

        if needsSetup {
            PostHogSDK.shared.setup(makeConfig(enabled: enabled))
        }
        // A choice the SDK saved on a previous launch beats `optOut` until optIn or optOut runs.
        if needsSetup || needsApply {
            apply(enabled)
        }
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        let started = didStart
        lock.unlock()
        // Turning off before the SDK was ever set up: nothing to opt out of, and no reason to set it up.
        guard enabled || started else { return }
        start(enabled: enabled)
    }

    func capture(name: String, properties: [String: String]) {
        // Dictionary is invariant, so the string map has to be copied into `[String: Any]`.
        var payload: [String: Any] = [:]
        payload.reserveCapacity(properties.count)
        for (key, value) in properties {
            payload[key] = value
        }
        PostHogSDK.shared.capture(name, properties: payload)
    }

    private func apply(_ enabled: Bool) {
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    private func makeConfig(enabled: Bool) -> PostHogConfig {
        let config = PostHogConfig(projectToken: projectToken, host: Self.host)
        config.optOut = !enabled
        // Anonymous events only. We never call identify, so no person profile is created.
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.disableGeoIp = true
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        // Our own events are the whole catalogue. Autocapture would read labels off the screen.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.captureAutocaptureElementText = false
        config.rageClickConfig.enabled = false
        config.sessionReplay = false
        config.surveys = false
        config.enableSwizzling = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.errorTrackingConfig.autoCapture = false
        config.errorTrackingConfig.exceptionSteps.enabled = false
        config.setBeforeSend { event in
            guard let properties = AnalyticsPayload.filtered(name: event.event, properties: event.properties) else {
                return nil
            }
            event.properties = properties
            return event
        }
        return config
    }
}
