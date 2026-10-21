import Foundation

/// A recorded payload copied into the test bundle (`MaisonTests/Fixtures`).
enum RecordedFixture {
    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Missing fixture \(name)" }
    }

    static func data(_ name: String, directory: String) throws -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: directory) {
            return try Data(contentsOf: url)
        }
        if let nested = bundle.resourceURL?.appending(path: directory).appending(path: "\(name).json"),
           FileManager.default.fileExists(atPath: nested.path) {
            return try Data(contentsOf: nested)
        }
        if let flat = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: flat)
        }
        throw Missing(name: "\(directory)/\(name).json")
    }

    static func json(_ name: String, directory: String = "Fixtures/HomeAssistant") throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data(name, directory: directory))
    }
}

/// Objective-C class so `Bundle(for:)` resolves the test bundle.
private final class FixtureAnchor: NSObject {}
