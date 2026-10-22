import Foundation
import Network
import Observation

/// Browses the local network for Home Assistant servers.
/// Starting it triggers the system Local Network permission prompt the first time.
@MainActor
@Observable
final class ServerDiscovery {
    private(set) var servers: [DiscoveredServer] = []
    private(set) var isBrowsing = false

    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_home-assistant._tcp", domain: nil),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let servers = Self.servers(from: results)
            MainActor.assumeIsolated {
                self?.servers = servers
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        isBrowsing = true
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private nonisolated static func servers(from results: Set<NWBrowser.Result>) -> [DiscoveredServer] {
        let servers = results.compactMap { result -> DiscoveredServer? in
            guard case .bonjour(let txtRecord) = result.metadata else { return nil }
            return DiscoveredServer(txtRecord: txtRecord.dictionary)
        }
        var seen = Set<String>()
        return servers
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
