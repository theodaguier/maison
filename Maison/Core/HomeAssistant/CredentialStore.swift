import Foundation
import Security

/// Persists Home Assistant credentials in the keychain, readable after the first unlock
/// so background refreshes keep working. Never synced to iCloud.
struct CredentialStore: Sendable {
    var service = "com.theodaguier.maison.credentials"
    var account = "home-assistant"

    func load() throws -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try JSONDecoder().decode(Credentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct KeychainError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return String(localized: "Couldn’t save the sign-in to the keychain: \(message)")
    }
}
