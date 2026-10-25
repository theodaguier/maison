import Foundation

// Accounts Maison makes for the people invited to the household, so they never sign in by hand.
// The commands are the ones Home Assistant's own Settings → People page sends; they need an administrator.

extension HomeAssistantConnection {
    /// Creates an administrator account that signs in with `username` and `password`, and the person
    /// it belongs to, so presence counts them. Returns the account's id.
    func createAdministrator(named name: String, username: String, password: String) async throws -> String {
        let created = try await send([
            "type": "config/auth/create",
            "name": .string(name),
            "group_ids": ["system-admin"],
            "local_only": false,
        ])
        guard let userID = created["user"]?["id"]?.stringValue else {
            throw HomeAssistantError.commandFailed(code: "invalid_format", message: "No user id")
        }
        try await send([
            "type": "config/auth_provider/homeassistant/create",
            "user_id": .string(userID),
            "username": .string(username),
            "password": .string(password),
        ])
        // Without a person the account still works; only "everyone left" wouldn't count them.
        _ = try? await send(["type": "person/create", "name": .string(name), "user_id": .string(userID)])
        return userID
    }

    /// Deletes an account Maison created, and the person linked to it.
    func deleteAccount(_ userID: String) async throws {
        let persons = try? await send(["type": "person/list"])
        if let person = persons?["storage"]?.arrayValue?.first(where: { $0["user_id"]?.stringValue == userID }),
           let personID = person["id"]?.stringValue {
            _ = try? await send(["type": "person/delete", "person_id": .string(personID)])
        }
        try await send(["type": "config/auth/delete", "user_id": .string(userID)])
    }

    /// Replaces the signed-in account's password.
    func changePassword(from current: String, to new: String) async throws {
        try await send([
            "type": "config/auth_provider/homeassistant/change_password",
            "current_password": .string(current),
            "new_password": .string(new),
        ])
    }
}

extension HomeAssistantAuth {
    /// Signs in with a username and password through the login flow behind the server's sign-in page,
    /// then exchanges the code it returns as the OAuth flow does.
    func signIn(username: String, password: String, now: Date = .now) async throws -> Credentials {
        let flow = try await post("auth/login_flow", [
            "client_id": .string(Self.clientID.absoluteString),
            "handler": ["homeassistant", .null],
            "redirect_uri": .string(Self.redirectURI.absoluteString),
        ])
        guard let flowID = flow["flow_id"]?.stringValue else {
            throw HomeAssistantError.authenticationFailed("No login flow")
        }
        let step = try await post("auth/login_flow/\(flowID)", [
            "client_id": .string(Self.clientID.absoluteString),
            "username": .string(username),
            "password": .string(password),
        ])
        guard step["type"]?.stringValue == "create_entry", let code = step["result"]?.stringValue else {
            throw HomeAssistantError.authenticationFailed(step["errors"]?["base"]?.stringValue)
        }
        return try await exchange(code: code, now: now)
    }

    private func post(_ path: String, _ body: [String: JSONValue]) async throws -> JSONValue {
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        let (data, response) = try await http.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if statusCode == 400 || statusCode == 403 {
                throw HomeAssistantError.authenticationFailed(String(data: data, encoding: .utf8))
            }
            throw HomeAssistantError.invalidResponse(statusCode: statusCode)
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension MemberAccess {
    /// A username no one types: Maison signs in with it once.
    static func makeUsername() -> String {
        "maison-" + UUID().uuidString.prefix(8).lowercased()
    }

    /// A random password, used once then replaced by one nobody knows.
    static func makePassword() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
    }
}
