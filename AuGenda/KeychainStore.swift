// KeychainStore.swift
// AuGenda
//
// Tiny Keychain wrapper for per-provider API keys.
//
// Design rules (per task-difficulty spec, "API key storage"):
//   * NEVER @AppStorage / UserDefaults — those sync via iCloud
//   * NEVER plain logging — never print key contents
//   * Per-device: a new device requires re-entering each key. We accept
//     this friction in exchange for the safety guarantee that no key is
//     ever pushed up to Apple's iCloud servers.
//   * Accessibility: kSecAttrAccessibleAfterFirstUnlock — readable while
//     device is locked after first unlock, so background auto-enrich can
//     still run while screen is off.
//
// Usage:
//   try KeychainStore.set("sk-...", for: .claude)
//   let key = try KeychainStore.get(for: .claude)   // nil if not set
//   try KeychainStore.remove(for: .claude)

import Foundation
import Security

enum KeychainStore {

    /// Single service name for all AuGenda keys; account is the provider's
    /// rawValue. Keeps keys clustered together in Keychain Access for
    /// easy audit / debug.
    private static let service = "com.augenda.AuGenda.aiprovider"

    /// Read a key. Returns nil if no key has been stored for this provider.
    /// Throws only on unexpected Keychain errors.
    static func get(for provider: AIProvider) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  provider.rawValue,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                throw KeychainError.decode
            }
            return str
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    /// Write (or replace) a key for this provider.
    /// Empty string is treated as a remove for convenience — passing ""
    /// from the settings UI when the user clears the field works without
    /// special-casing on the caller side.
    static func set(_ value: String, for provider: AIProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try remove(for: provider)
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.encode
        }

        // Try to update an existing entry first
        let queryUpdate: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  provider.rawValue
        ]
        let attrsUpdate: [String: Any] = [
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(queryUpdate as CFDictionary, attrsUpdate as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Insert new
            let queryAdd: [String: Any] = [
                kSecClass as String:        kSecClassGenericPassword,
                kSecAttrService as String:  service,
                kSecAttrAccount as String:  provider.rawValue,
                kSecValueData as String:    data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            let addStatus = SecItemAdd(queryAdd as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
        default:
            throw KeychainError.osStatus(updateStatus)
        }
    }

    /// Delete a key. No-op (no throw) if not present.
    static func remove(for provider: AIProvider) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Quick "is a key stored?" check for the Settings UI. Doesn't return
    /// the value — Settings reads the masked form via `get` only when it
    /// needs to display the obscured input field.
    static func hasKey(for provider: AIProvider) -> Bool {
        (try? get(for: provider)) != nil
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case encode
    case decode
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encode:             return "Couldn't encode the key for storage."
        case .decode:             return "Couldn't decode the stored key."
        case .osStatus(let code): return "Keychain error (\(code))."
        }
    }
}
