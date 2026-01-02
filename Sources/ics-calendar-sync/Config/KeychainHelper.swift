import Foundation
import Security

// MARK: - Keychain Helper

/// Helper for securely storing and retrieving credentials from macOS Keychain
enum KeychainHelper {
    private static let service = "com.ics-calendar-sync"

    // MARK: - Save

    /// Save a string value to the keychain
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete any existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    /// Load a string value from the keychain
    static func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return value
    }

    // MARK: - Delete

    /// Delete a value from the keychain
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Exists

    /// Check if a key exists in the keychain
    static func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - List Keys

    /// List all keys stored for this service
    static func listKeys() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for keychain"
        case .decodingFailed:
            return "Failed to decode value from keychain"
        case .saveFailed(let status):
            return "Failed to save to keychain: \(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString)"
        case .loadFailed(let status):
            return "Failed to load from keychain: \(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString)"
        }
    }
}

// MARK: - Convenience Keys

extension KeychainHelper {
    /// Standard key names
    enum Keys {
        static let authToken = "auth_token"
        static let username = "username"
        static let password = "password"
    }

    /// Save auth token
    static func saveAuthToken(_ token: String) throws {
        try save(key: Keys.authToken, value: token)
    }

    /// Load auth token
    static func loadAuthToken() throws -> String? {
        try load(key: Keys.authToken)
    }

    /// Save basic auth credentials
    static func saveBasicAuth(username: String, password: String) throws {
        try save(key: Keys.username, value: username)
        try save(key: Keys.password, value: password)
    }

    /// Load basic auth credentials
    static func loadBasicAuth() throws -> (username: String, password: String)? {
        guard let username = try load(key: Keys.username),
              let password = try load(key: Keys.password) else {
            return nil
        }
        return (username, password)
    }

    /// Delete all stored credentials
    static func deleteAllCredentials() throws {
        try? delete(key: Keys.authToken)
        try? delete(key: Keys.username)
        try? delete(key: Keys.password)
    }
}
