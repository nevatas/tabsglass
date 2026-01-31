//
//  KeychainService.swift
//  tabsglass
//
//  Secure storage for authentication tokens using iOS Keychain
//

import Foundation
import Security

/// Keys for Keychain storage
enum KeychainKey: String {
    case accessToken = "com.tabsglass.accessToken"
    case refreshToken = "com.tabsglass.refreshToken"
    case userEmail = "com.tabsglass.userEmail"
}

/// Errors that can occur during Keychain operations
enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .loadFailed(let status):
            return "Failed to load from Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .dataConversionFailed:
            return "Failed to convert data"
        case .itemNotFound:
            return "Item not found in Keychain"
        }
    }
}

/// Service for secure token storage in iOS Keychain
final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let service = "com.tabsglass"

    private init() {}

    // MARK: - Public API

    /// Save a string value to the Keychain
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        // Delete any existing item first
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Load a string value from the Keychain
    func load(_ key: KeychainKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        return string
    }

    /// Delete a value from the Keychain
    func delete(_ key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Clear all stored tokens
    func clearAll() {
        try? delete(.accessToken)
        try? delete(.refreshToken)
        try? delete(.userEmail)
    }

    /// Check if user has stored tokens (potentially logged in)
    func hasTokens() -> Bool {
        (try? load(.accessToken)) != nil && (try? load(.refreshToken)) != nil
    }
}
