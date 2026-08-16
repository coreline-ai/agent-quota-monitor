import Foundation
import Security

protocol SecretStore: Sendable {
    func read(account: String) async throws -> Data?
    func replace(_ value: Data, account: String) async throws
    func delete(account: String) async throws
}

enum SecretStoreError: Error {
    case unexpectedStatus(OSStatus)
}

actor KeychainStore: SecretStore {
    private let service: String

    init(service: String = AppMetadata.bundleIdentifier) {
        self.service = service
    }

    func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
        return result as? Data
    }

    func replace(_ value: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes = [kSecValueData as String: value]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = value
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError.unexpectedStatus(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
