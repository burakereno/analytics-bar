import Foundation
import Security

enum KeychainTokenStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct KeychainTokenStore: TokenStore, Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "com.burakerenoglu.AnalyticsBar.google-oauth",
        account: String = "primary"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> GoogleOAuthToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let token = try? JSONDecoder().decode(GoogleOAuthToken.self, from: data) else {
            throw KeychainTokenStoreError.invalidData
        }
        return token
    }

    func save(_ token: GoogleOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainTokenStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
