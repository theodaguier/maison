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
        if isDemoHome {
            // As the server words it, markdown image and all: Maison cleans it.
            let link = language == "fr"
                ? "Cliquez sur « Soumettre », puis touchez la flèche droite sur le routeur pour enregistrer Freebox avec Home Assistant.\n\n![Emplacement du bouton sur le routeur](/static/images/config_freebox.png)"
                : "Click \"Submit\", then touch the right arrow on the router to register Freebox with Home Assistant.\n\n![Location of button on the router](/static/images/config_freebox.png)"
            return FlowWording(domain: domain, resources: ["component.\(domain).config.step.link.description": link])
        }
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

    /// Adds, without asking anything, the most used integration that provides what `categories` describe
    /// and needs no answer from the person. Returns its name, or `nil` when every one needs the person.
    func addAutomatically(_ categories: [String]) async -> String? {
        if isDemoHome { return IntegrationDescription.serving(categories, in: DemoHome.integrationCatalog).first?.name }
        guard let driver = await flowDriver() else { return nil }
        let installed = Set(integrations.map(\.domain))
        let candidates = IntegrationDescription.serving(categories, in: await integrationCatalog()).filter { !installed.contains($0.domain) }
        guard let added = await driver.addFirstAskingNothing(Array(candidates.prefix(4))) else { return nil }
        await integrationAdded(added.domain)
        return added.name
    }

    /// Adds the internet check now rather than at the next daily try.
    func addInternetCheck() async {
        UserDefaults.standard.removeObject(forKey: InternetCheckSetting.attemptedKey)
        await setUpServer()
    }
}
