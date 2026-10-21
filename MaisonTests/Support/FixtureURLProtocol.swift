import Foundation
@testable import Maison

/// One HTTP response served without opening a socket.
struct FixtureHTTPResponse: Sendable {
    var status: Int
    var body: Data
    var failure: URLError?

    static func json(named name: String, status: Int = 200) throws -> FixtureHTTPResponse {
        FixtureHTTPResponse(status: status, body: try RecordedFixture.data(name, directory: "Fixtures/HomeAssistant"), failure: nil)
    }

    static let timedOut = FixtureHTTPResponse(status: 0, body: Data(), failure: URLError(.timedOut))
}

/// `URLProtocol` stub. Install a handler, then talk through `session()` — requests never leave the process.
final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> FixtureHTTPResponse

    /// A `let` so the static itself is not shared mutable state. The lock guards `handler`.
    private static let state = State()

    static func install(_ handler: @escaping Handler) {
        state.set(handler)
    }

    static func reset() {
        state.set(nil)
    }

    /// Ephemeral session whose only protocol is this stub.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func client(serving handler: @escaping Handler) -> URLSessionHTTPClient {
        install(handler)
        return URLSessionHTTPClient(session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.state.get()
        guard let client else { return }
        guard let handler else {
            client.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let response = try handler(request)
            if let failure = response.failure {
                client.urlProtocol(self, didFailWithError: failure)
                return
            }
            let url = request.url ?? URL(string: "https://fixture.invalid")!
            let http = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: response.body)
            client.urlProtocolDidFinishLoading(self)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func set(_ handler: Handler?) {
            lock.withLock { self.handler = handler }
        }

        func get() -> Handler? {
            lock.withLock { handler }
        }
    }
}

extension URLRequest {
    /// Body either set on the request or streamed by `URLSession`.
    var fixtureBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
