import Foundation
import Network

/// The network the iPhone goes through: whether it reaches one, by which interfaces and gateways.
/// Another Wi-Fi keeps the interface but changes the gateway.
struct NetworkRoute: Sendable, Equatable {
    var isReachable: Bool
    var interfaces: [String]
    var gateways: [String]

    init(isReachable: Bool, interfaces: [String] = [], gateways: [String] = []) {
        self.isReachable = isReachable
        self.interfaces = interfaces
        self.gateways = gateways
    }

    init(_ path: NWPath) {
        self.init(
            isReachable: path.status == .satisfied,
            interfaces: path.availableInterfaces.map(\.name),
            gateways: path.gateways.map(\.debugDescription)
        )
    }

    /// Worth reconnecting: a network is reached, and it isn't the one the iPhone was on.
    /// Losing every network is not: there is nothing to reconnect through, and the ping notices it.
    func isChange(from previous: NetworkRoute) -> Bool {
        isReachable && self != previous
    }

    /// Yields each time the iPhone reaches a network other than the one it was on.
    /// The network it is on when watching starts is not a change.
    static func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                var previous: NetworkRoute?
                for await path in NWPathMonitor() {
                    let route = NetworkRoute(path)
                    if let previous, route.isChange(from: previous) {
                        continuation.yield()
                    }
                    previous = route
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
