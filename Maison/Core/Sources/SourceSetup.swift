import Foundation

// What Settings › All Sources asks the server: its catalog of integrations, the devices it found,
// and a flow to run. Adding needs an administrator, as in Home Assistant.

extension HomeStore {
    var isAdministrator: Bool { currentUser?.isAdmin == true }

    func integrationCatalog() async -> [IntegrationDescription] {
        if isDemoHome { return DemoHome.integrationCatalog }
        guard let connection else { return [] }
        return (try? await connection.integrationCatalog()) ?? []
    }

    func discoveredDevices() async -> [DiscoveredDevice] {
        if isDemoHome { return DemoHome.discoveredDevices }
        guard isAdministrator, let connection else { return [] }
        return (try? await connection.discoveredDevices()) ?? []
    }

    /// Runs flows with a token that is still valid; `nil` for someone who isn't an administrator.
    func flowDriver() async -> (any FlowDriver)? {
        if isDemoHome { return DemoFlowDriver() }
        guard isAdministrator, let credentials = try? await freshCredentials() else { return nil }
        return ConfigFlowClient(serverURL: activeURL ?? credentials.serverURL, accessToken: credentials.accessToken)
    }

    /// The flow's words in the iPhone's language, which the server translates.
    func flowWording(domain: String) async -> FlowWording {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard !isDemoHome, let connection, let resources = try? await connection.flowTranslations(domain: domain, language: language)
        else { return FlowWording(domain: domain, resources: [:]) }
        return FlowWording(domain: domain, resources: resources)
    }

    /// After an integration is added: noted in Settings, and its devices read.
    func integrationAdded(_ domain: String) async {
        ServerSetupLog.recordAdded(domain)
        guard !isDemoHome else { return }
        await connect()
    }

    /// Adds the internet check now rather than at the next daily try.
    func addInternetCheck() async {
        UserDefaults.standard.removeObject(forKey: InternetCheckSetting.attemptedKey)
        await setUpServer()
    }
}
