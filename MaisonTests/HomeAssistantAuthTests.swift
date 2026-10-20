import Foundation
import Testing
@testable import Maison

struct HomeAssistantAuthTests {
    let server = URL(string: "http://192.168.1.179:8123")!

    @Test func buildsTheAuthorizationURL() throws {
        let url = HomeAssistantAuth(serverURL: server).authorizationURL(state: "abc")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.path == "/auth/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "https://theodaguier.me/maison/")
        #expect(query["redirect_uri"] == "maison://auth-callback")
        #expect(query["state"] == "abc")
    }

    @Test func readsTheCodeFromTheCallback() throws {
        let callback = URL(string: "maison://auth-callback?code=xyz&state=abc")!
        #expect(try HomeAssistantAuth.authorizationCode(from: callback, expectedState: "abc") == "xyz")
    }

    @Test func rejectsACallbackWithAnotherState() {
        let callback = URL(string: "maison://auth-callback?code=xyz&state=forged")!
        #expect(throws: HomeAssistantError.invalidCallback) {
            try HomeAssistantAuth.authorizationCode(from: callback, expectedState: "abc")
        }
    }

    @Test func exchangesTheCodeForTokens() async throws {
        let request = Captured<URLRequest>()
        let http = StubHTTPClient(
            body: #"{"access_token":"access","expires_in":1800,"refresh_token":"refresh","token_type":"Bearer"}"#,
            onRequest: { request.set($0) }
        )
        let now = Date(timeIntervalSince1970: 1_000)

        let credentials = try await HomeAssistantAuth(serverURL: server, http: http).exchange(code: "xyz", now: now)

        #expect(credentials == Credentials(
            serverURL: server, accessToken: "access", refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 2_800)
        ))
        let sent = try #require(request.value)
        #expect(sent.url?.path() == "/auth/token")
        #expect(sent.httpMethod == "POST")
        let body = String(decoding: try #require(sent.httpBody), as: UTF8.self)
        #expect(body == "client_id=https://theodaguier.me/maison/&code=xyz&grant_type=authorization_code")
    }

    @Test func refreshKeepsTheRefreshToken() async throws {
        let http = StubHTTPClient(body: #"{"access_token":"new","expires_in":1800,"token_type":"Bearer"}"#)
        let old = Credentials(serverURL: server, accessToken: "old", refreshToken: "refresh", expiresAt: .distantPast)

        let refreshed = try await HomeAssistantAuth(serverURL: server, http: http).refresh(old, now: Date(timeIntervalSince1970: 0))

        #expect(refreshed.accessToken == "new")
        #expect(refreshed.refreshToken == "refresh")
        #expect(refreshed.expiresAt == Date(timeIntervalSince1970: 1_800))
    }

    @Test func reportsARevokedRefreshToken() async throws {
        let http = StubHTTPClient(statusCode: 400, body: #"{"error":"invalid_grant"}"#)
        let old = Credentials(serverURL: server, accessToken: "old", refreshToken: "revoked", expiresAt: .distantPast)

        await #expect(throws: HomeAssistantError.authenticationFailed(#"{"error":"invalid_grant"}"#)) {
            try await HomeAssistantAuth(serverURL: server, http: http).refresh(old)
        }
    }

    @Test func treatsTokensAsExpiredOneMinuteEarly() {
        let credentials = Credentials(serverURL: server, accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1_000))
        #expect(!credentials.isExpired(at: Date(timeIntervalSince1970: 900)))
        #expect(credentials.isExpired(at: Date(timeIntervalSince1970: 950)))
    }
}
