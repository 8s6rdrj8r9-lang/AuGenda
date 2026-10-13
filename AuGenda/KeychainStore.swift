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
//   * Accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly —
//     readable while the device is locked after first unlock (so background
//     auto-enrich still runs with the screen off), but the ThisDeviceOnly
//     suffix is load-bearing: it keeps the key OUT of encrypted iCloud
//     device backups and off iCloud Keychain, which is what actually backs
//     the "never leaves this device" guarantee above.
//
// Usage:
//   try KeychainStore.set("sk-...", for: .claude)
//   let key = try KeychainStore.get(for: .claude)   // nil if not set
//   try KeychainStore.remove(for: .claude)

import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "KeychainStore")

enum KeychainStore {

    /// Single service name for all AuGenda keys; account is the provider's
    /// rawValue. Keeps keys clustered together in Keychain Access for
    /// easy audit / debug.
    private static let service = "com.augenda.AuGenda.aiprovider"

    /// Read a key. Returns nil if no key has been stored for this provider.
    /// Throws only on unexpected Keychain errors.
    static func get(for provider: AIProvider) throws -> String? {
        try getString(service: service, account: provider.rawValue)
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

        guard let data = trimmed.data(using: .utf8) else { throw KeychainError.encode }
        try setData(data, service: service, account: provider.rawValue)
    }

    /// Delete a key. No-op (no throw) if not present.
    static func remove(for provider: AIProvider) throws {
        try remove(service: service, account: provider.rawValue)
    }

    /// Quick "is a key stored?" check for the Settings UI. Doesn't return
    /// the value — Settings reads the masked form via `get` only when it
    /// needs to display the obscured input field.
    static func hasKey(for provider: AIProvider) -> Bool {
        do {
            return try get(for: provider) != nil
        } catch {
            logger.error("Keychain hasKey check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - String-based non-throwing API (for tests and general use)

    static func get(for account: String) -> String? {
        do {
            return try get(account: account)
        } catch {
            logger.error("Keychain get failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func set(_ value: String, for account: String) {
        do {
            try set(value: value, account: account)
        } catch {
            logger.error("Keychain set failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func remove(for account: String) {
        do {
            try remove(account: account)
        } catch {
            logger.error("Keychain remove failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func removeAll(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Shared throwing implementations

    static func getData(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.decode }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    static func setData(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try addData(data, service: service, account: account)
        case errSecInteractionNotAllowed, errSecAuthFailed:
            try remove(service: service, account: account)
            try addData(data, service: service, account: account)
        default:
            throw KeychainError.osStatus(updateStatus)
        }
    }

    static func remove(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    private static func getString(service: String, account: String) throws -> String? {
        guard let data = try getData(service: service, account: account) else { return nil }
        guard let str = String(data: data, encoding: .utf8) else {
            throw KeychainError.decode
        }
        return str
    }

    private static func addData(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
    }

    // MARK: - Internal string implementations

    private static func get(account: String) throws -> String? {
        try getString(service: service, account: account)
    }

    private static func set(value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try remove(account: account)
            return
        }

        guard let data = trimmed.data(using: .utf8) else { throw KeychainError.encode }
        try setData(data, service: service, account: account)
    }

    private static func remove(account: String) throws {
        try remove(service: service, account: account)
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
