import Foundation

/// A Home Assistant server announced on the local network through Bonjour (`_home-assistant._tcp`).
struct DiscoveredServer: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let version: String?
    let url: URL

    /// Builds a server from the TXT record Home Assistant publishes
    /// (`uuid`, `location_name`, `version`, `internal_url`, `base_url`, `external_url`).
    init?(txtRecord: [String: String]) {
        let candidates = ["internal_url", "base_url", "external_url"]
            .compactMap { txtRecord[$0] }
            .filter { !$0.isEmpty }
        guard let url = candidates.lazy.compactMap(URL.init(string:)).first(where: { $0.host() != nil }) else {
            return nil
        }
        self.url = url
        self.id = txtRecord["uuid"].flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString
        self.name = txtRecord["location_name"].flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? "Home Assistant"
        self.version = txtRecord["version"].flatMap { $0.isEmpty ? nil : $0 }
    }
}
