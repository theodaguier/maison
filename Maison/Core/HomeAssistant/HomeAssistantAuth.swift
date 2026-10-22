import Foundation

/// Tokens for one Home Assistant server, obtained through its OAuth flow.
struct Credentials: Sendable, Hashable, Codable {
    /// The address used to sign in, usually the local one.
    let serverURL: URL
    var accessToken: String
    let refreshToken: String
    var expiresAt: Date
    /// The address that works away from home: Home Assistant's external URL, or Home Assistant Cloud's.
    var remoteURL: URL?

    func isExpired(at now: Date = .now) -> Bool {
        now.addingTimeInterval(60) >= expiresAt
    }

    /// Where to reach the server, local first. The same tokens work through every address.
    var addresses: [URL] {
        [serverURL, remoteURL].compactMap(\.self).reduce(into: []) { addresses, url in
            if !addresses.contains(url) { addresses.append(url) }
        }
    }
}

enum HomeAssistantError: Error, Equatable {
    case invalidResponse(statusCode: Int)
    case invalidCallback
    case authenticationFailed(String?)
    case connectionClosed
    case commandFailed(code: String, message: String)
}

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Home Assistant's OAuth 2 / IndieAuth flow.
///
/// Home Assistant identifies clients by a URL. Because the redirect URI uses a custom scheme on a
/// different host, the page at `clientID` must declare it with
/// `<link rel="redirect_uri" href="maison://auth-callback">`.
struct HomeAssistantAuth: Sendable {
    static let clientID = URL(string: "https://theodaguier.github.io/maison/")!
    static let callbackScheme = "maison"
    static let redirectURI = URL(string: "maison://auth-callback")!

    let serverURL: URL
    var http: any HTTPClient = URLSessionHTTPClient()

    func authorizationURL(state: String) -> URL {
        serverURL.appending(path: "auth/authorize").appending(queryItems: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID.absoluteString),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
        ])
    }

    /// Extracts the authorization code from the callback URL, checking it answers our request.
    static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard
            items.first(where: { $0.name == "state" })?.value == expectedState,
            let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else {
            throw HomeAssistantError.invalidCallback
        }
        return code
    }

    func exchange(code: String, now: Date = .now) async throws -> Credentials {
        let response = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": Self.clientID.absoluteString,
        ])
        guard let refreshToken = response.refreshToken else {
            throw HomeAssistantError.authenticationFailed("Missing refresh token")
        }
        return Credentials(
            serverURL: serverURL,
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(response.expiresIn)
        )
    }

    func refresh(_ credentials: Credentials, now: Date = .now) async throws -> Credentials {
        let response = try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": Self.clientID.absoluteString,
        ])
        var refreshed = credentials
        refreshed.accessToken = response.accessToken
        refreshed.expiresAt = now.addingTimeInterval(response.expiresIn)
        return refreshed
    }

    private func requestToken(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: serverURL.appending(path: "auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await http.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if statusCode == 400 || statusCode == 403 {
                throw HomeAssistantError.authenticationFailed(String(data: data, encoding: .utf8))
            }
            throw HomeAssistantError.invalidResponse(statusCode: statusCode)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
