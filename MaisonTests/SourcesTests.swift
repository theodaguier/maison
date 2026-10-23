import Foundation
@testable import Maison
import Testing

struct SourcesTests {
    @Test func keepsOnlyIntegrationsThatCanBeAdded() {
        let result: JSONValue = [
            "core": ["integration": [
                "shelly": ["name": "Shelly", "config_flow": true, "iot_class": "local_push", "integration_type": "device"],
                "google": ["name": "Google", "integrations": [
                    "google_assistant": ["name": "Google Assistant", "config_flow": false],
                    "nest": ["name": "Google Nest", "config_flow": true, "iot_class": "cloud_push"],
                ]],
                "ikea": ["name": "IKEA", "integration_type": "virtual", "config_flow": true],
                "template": ["name": "Template", "config_flow": false],
            ]],
            "custom": ["integration": ["myhome": ["name": "My Home", "config_flow": true]]],
        ]
        let catalog = IntegrationDescription.parse(result)
        #expect(catalog.map(\.domain) == ["nest", "myhome", "shelly"])
        #expect(catalog.first { $0.domain == "nest" }?.isCloud == true)
        #expect(catalog.first { $0.domain == "shelly" }?.isCloud == false)
    }

    @Test func searchIgnoresAccentsAndPutsPrefixesFirst() {
        let catalog = [
            IntegrationDescription(domain: "meteo_france", name: "Météo-France", iotClass: "cloud_polling"),
            IntegrationDescription(domain: "met", name: "Meteorologisk institutt (Met.no)", iotClass: "cloud_polling"),
            IntegrationDescription(domain: "accuweather", name: "AccuWeather", iotClass: "cloud_polling"),
        ]
        #expect(IntegrationDescription.search("meteo", in: catalog).map(\.domain) == ["meteo_france", "met"])
        #expect(IntegrationDescription.search("weather", in: catalog).map(\.domain) == ["accuweather"])
        #expect(IntegrationDescription.search("  ", in: catalog).isEmpty)
    }

    @Test func readsTheFieldsOfAForm() {
        let step = FlowStep.parse([
            "type": "form", "flow_id": "f1", "step_id": "user",
            "data_schema": [
                ["name": "host", "type": "string", "required": true],
                ["name": "password", "type": "string"],
                ["name": "api_key", "selector": ["text": ["type": "password"]], "required": true],
                ["name": "port", "type": "integer", "default": 80],
                ["name": "scan_interval", "selector": ["number": ["step": 0.5]]],
                ["name": "ssl", "type": "boolean"],
                ["name": "region", "type": "select", "options": [["eu", "Europe"], ["us", "United States"]]],
                ["name": "mode", "selector": ["select": ["options": [["value": "a", "label": "A"], "b"]]]],
                ["name": "location", "selector": ["location": [:]], "required": true],
            ],
            "errors": ["base": "cannot_connect"],
        ])
        guard case .form(let form) = step else { Issue.record("Not a form"); return }
        #expect(form.fields.map(\.kind) == [
            .text(isSecret: false), .text(isSecret: true), .text(isSecret: true), .number(isInteger: true),
            .number(isInteger: false), .toggle,
            .choice([.init(value: "eu", label: "Europe"), .init(value: "us", label: "United States")]),
            .choice([.init(value: "a", label: "A"), .init(value: "b", label: "b")]),
            .unsupported("location"),
        ])
        #expect(form.fields[3].defaultValue == 80)
        #expect(form.errors == ["base": "cannot_connect"])
        #expect(form.hasUnsupportedRequirement)
    }

    @Test func readsTheOtherSteps() {
        #expect(FlowStep.parse(["type": "menu", "flow_id": "f", "step_id": "user", "menu_options": ["cloud", "local"]])
            == .menu(flowID: "f", stepID: "user", options: ["cloud", "local"]))
        #expect(FlowStep.parse(["type": "menu", "flow_id": "f", "step_id": "user", "menu_options": ["local": "Local", "cloud": "Cloud"]])
            == .menu(flowID: "f", stepID: "user", options: ["cloud", "local"]))
        #expect(FlowStep.parse(["type": "external", "flow_id": "f", "step_id": "auth", "url": "https://example.com/authorize"])
            == .external(flowID: "f", stepID: "auth", url: URL(string: "https://example.com/authorize")!))
        #expect(FlowStep.parse(["type": "external_done", "flow_id": "f", "step_id": "auth"]) == .progress(flowID: "f", stepID: "auth"))
        #expect(FlowStep.parse(["type": "create_entry", "title": "Salon"]) == .created(title: "Salon"))
        #expect(FlowStep.parse(["type": "abort", "reason": "missing_credentials"]) == .aborted(reason: "missing_credentials"))
    }

    @Test func wordsAFlowFromItsTranslations() {
        let wording = FlowWording(domain: "shelly", resources: [
            "component.shelly.config.step.user.data.host": "Hôte",
            "component.shelly.config.step.user.description": "Avant de configurer {name}, appuyez sur le bouton.",
            "component.shelly.config.abort.missing_credentials": "Identifiants manquants",
        ])
        #expect(wording.label(field: "host", step: "user") == "Hôte")
        #expect(wording.label(field: "api_key", step: "user") == "Api Key")
        #expect(wording.description(step: "user", placeholders: ["name": "Prise cuisine"]) == "Avant de configurer Prise cuisine, appuyez sur le bouton.")
        #expect(wording.abort("missing_credentials") == "Identifiants manquants")
        #expect(wording.abort("other") == nil)
    }

    @Test func listsFoundDevicesWithTheirNames() async throws {
        let progress: JSONValue = [
            ["flow_id": "d1", "handler": "shelly", "context": ["source": "zeroconf", "title_placeholders": ["name": "Prise cuisine"]]],
            ["flow_id": "u1", "handler": "hue", "context": ["source": "user"]],
            ["flow_id": "d2", "handler": "freebox", "context": ["source": "zeroconf"]],
        ]
        let transport = FakeTransport { message in
            switch message["type"]?.stringValue {
            case "auth": [["type": "auth_ok", "ha_version": "2026.8.1"]]
            case "config_entries/flow/progress": [result(for: message, progress)]
            default: [result(for: message)]
            }
        }
        let connection = HomeAssistantConnection(transport: transport, accessToken: "token")
        try await connection.connect()
        let devices = try await connection.discoveredDevices()
        #expect(devices == [DiscoveredDevice(flowID: "d1", domain: "shelly", name: "Prise cuisine"),
                            DiscoveredDevice(flowID: "d2", domain: "freebox", name: nil)])
    }

    @MainActor
    @Test func theSampleHomeSaysWhatIsThereAndWhatIsMissing() {
        let store = DemoHome.store()
        var facts = SourceFacts()
        facts.tariff = DemoHome.tariff
        let sources = store.dataSources(facts)
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        #expect(byID["temperature"]?.isInPlace == true)
        #expect(byID["meter"]?.state == .missing)
        #expect(byID["tariff"]?.state == .entered(String(localized: "Entered")))
        #expect(byID["water"]?.isInPlace == true)
        #expect(byID["internet"]?.isInPlace == true)
        #expect(byID["presence"]?.state == .missing)
        // A capability, never a brand, and every section has rows.
        #expect(Set(sources.map(\.section)) == Set(SourceSection.allCases))

        let coverage = HomeStore.coverage(of: sources)
        #expect(coverage.map(\.section) == [.comfort, .energy, .network])
        let energy = coverage[1]
        #expect(energy.total == sources.count { $0.section == .energy })
        #expect(!energy.isMeasured)
        #expect(coverage[0].isMeasured && coverage[2].isMeasured)
    }

    @MainActor
    @Test func aMeterMakesEnergyMeasured() {
        let store = DemoHome.store()
        var facts = SourceFacts()
        facts.meterIDs = ["sensor.linky"]
        let coverage = HomeStore.coverage(of: store.dataSources(facts))
        #expect(coverage[1].isMeasured)
    }
}
