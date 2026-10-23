import Foundation
@testable import Maison
import Testing

struct IntegrationCategoriesTests {
    private let ping = IntegrationDescription(domain: "ping", name: "Ping (ICMP)", iotClass: "local_polling")
    private let calendar = IntegrationDescription(domain: "google", name: "Google Calendar", iotClass: "cloud_polling")
    private let plug = IntegrationDescription(domain: "shelly", name: "Shelly", iotClass: "local_push")

    @Test func comesFromHomeAssistantsOwnCategories() throws {
        let profile = try #require(IntegrationCategories.all["ping"])
        #expect(profile.categories.contains("computers_network.monitoring"))
        #expect(profile.installs > 0)
        #expect(IntegrationCategories.all.count > 500)
    }

    @Test func groupsByThePartOfTheHomeServed() {
        #expect(IntegrationGroup.of(["computers_network.monitoring", "presence_location.network_presence"]) == [.network, .presence])
        #expect(IntegrationGroup.of(["plugs_switches", "lighting.bulbs_lamps"]) == [.energy])
        #expect(IntegrationGroup.of(["productivity_information.calendars_todos"]) == [.other])
        #expect(IntegrationGroup.of([]) == [.other])
    }

    @Test func aSourceOnlyOffersWhatServesIt() {
        let internet = IntegrationDescription.serving(DataSource.categories["internet"] ?? [], in: [ping, calendar, plug])
        #expect(internet.map(\.domain) == ["ping"])
        #expect(ping.groups.contains(.network))
        #expect(calendar.groups == [.other])
    }

    @Test func aStepAsksNothingWhenEveryAnswerIsKnown() {
        func form(_ fields: [FlowField], errors: [String: String] = [:]) -> FlowStep.Form {
            FlowStep.Form(flowID: "f", stepID: "user", fields: fields, errors: errors, placeholders: [:])
        }
        let located = FlowField(name: "latitude", kind: .number(isInteger: false), isRequired: true, defaultValue: 48.85)
        let name = FlowField(name: "name", kind: .text(isSecret: false), isRequired: true, defaultValue: "Maison")
        let optional = FlowField(name: "track_home", kind: .toggle, isRequired: false, defaultValue: nil)
        let host = FlowField(name: "host", kind: .text(isSecret: false), isRequired: true, defaultValue: nil)
        let empty = FlowField(name: "host", kind: .text(isSecret: false), isRequired: true, defaultValue: "")

        func step(_ id: String) -> FlowStep.Form { FlowStep.Form(flowID: "f", stepID: id, fields: [], errors: [:], placeholders: [:]) }
        #expect(step("discovery_confirm").asksNothing)
        // Pressing the button on the box or the bridge is the person's to do.
        #expect(!step("link").asksNothing)
        #expect(!step("pair").asksNothing)
        #expect(form([located, name, optional]).asksNothing)
        #expect(form([located, name, optional]).defaultAnswers == ["latitude": 48.85, "name": "Maison"])
        #expect(!form([located, host]).asksNothing)
        #expect(!form([empty]).asksNothing)
        #expect(!form([located], errors: ["base": "cannot_connect"]).asksNothing)
    }

    @Test func addsTheFirstOneThatAsksNothingAndDropsTheOthers() async {
        let driver = ScriptedFlowDriver(steps: [
            "needs_key": .form(.init(flowID: "a", stepID: "user",
                                     fields: [FlowField(name: "api_key", kind: .text(isSecret: true), isRequired: true, defaultValue: nil)],
                                     errors: [:], placeholders: [:])),
            "met": .form(.init(flowID: "b", stepID: "user",
                               fields: [FlowField(name: "name", kind: .text(isSecret: false), isRequired: true, defaultValue: "Maison")],
                               errors: [:], placeholders: [:])),
        ])
        let added = await driver.addFirstAskingNothing([
            IntegrationDescription(domain: "needs_key", name: "Needs a key", iotClass: "cloud_polling"),
            IntegrationDescription(domain: "met", name: "Met.no", iotClass: "cloud_polling"),
        ])
        #expect(added?.domain == "met")
        #expect(await driver.cancelled == ["a"])
        #expect(await driver.submitted == [["b": ["name": "Maison"]]])
    }

    @Test func leavesABoxThatWaitsForItsButton() async throws {
        let http = ScriptedHTTPClient { _ in (200, #"{"type": "form", "flow_id": "fbx", "step_id": "link", "data_schema": []}"#) }
        let outcome = try await ConfigFlowClient(serverURL: URL(string: "http://homeassistant.local:8123")!, accessToken: "token", client: http)
            .confirmIfNothingToAsk(flowID: "fbx")
        #expect(outcome == nil)
        #expect(http.sent.map(\.httpMethod) == ["GET"])
    }

    @Test func confirmsAFoundDeviceWhoseFieldsHaveDefaults() async throws {
        let http = ScriptedHTTPClient { request in
            request.httpMethod == "GET"
                ? (200, #"{"type": "form", "flow_id": "d3", "step_id": "discovery_confirm", "data_schema": [{"name": "host", "type": "string", "required": true, "default": "192.168.1.20"}]}"#)
                : (200, #"{"type": "create_entry", "result": {"entry_id": "entry-plug"}}"#)
        }
        let outcome = try await ConfigFlowClient(serverURL: URL(string: "http://homeassistant.local:8123")!, accessToken: "token", client: http)
            .confirmIfNothingToAsk(flowID: "d3")
        #expect(outcome == .created(entryID: "entry-plug"))
        #expect(String(decoding: http.sent[1].httpBody ?? Data(), as: UTF8.self).contains("192.168.1.20"))
    }
}

/// Starts each domain on a given step; any answer creates the entry.
private actor ScriptedFlowDriver: FlowDriver {
    let steps: [String: FlowStep]
    var cancelled: [String] = []
    var submitted: [[String: [String: JSONValue]]] = []

    init(steps: [String: FlowStep]) { self.steps = steps }

    func start(_ domain: String) async throws -> FlowStep { steps[domain] ?? .aborted(reason: "unknown") }
    func current(_ flowID: String) async throws -> FlowStep { .aborted(reason: "unknown") }
    func submit(_ flowID: String, answers: [String: JSONValue]) async throws -> FlowStep {
        submitted.append([flowID: answers])
        return .created(title: flowID)
    }

    func cancel(_ flowID: String) async { cancelled.append(flowID) }
}
