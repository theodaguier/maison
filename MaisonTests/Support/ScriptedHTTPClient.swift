import Foundation
@testable import Maison

/// Answers each request with the reply for its path, and keeps what was sent.
final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private let reply: @Sendable (URLRequest) -> (status: Int, body: String)
    private var requests: [URLRequest] = []

    init(_ reply: @escaping @Sendable (URLRequest) -> (status: Int, body: String)) {
        self.reply = reply
    }

    var sent: [URLRequest] { lock.withLock { requests } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { requests.append(request) }
        let (status, body) = reply(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
