//
//  KeychainCredentialStore.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation
import Security

struct KeychainCredentialStore {
    enum StoreError: Error {
        case invalidPassword
        case unhandledStatus(OSStatus)
    }

    private let service = "MailCode.emailCredential"

    func saveAppPassword(_ password: String, for emailAddress: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw StoreError.invalidPassword
        }

        let query = baseQuery(for: emailAddress)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw StoreError.unhandledStatus(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StoreError.unhandledStatus(addStatus)
        }
    }

    func loadAppPassword(for emailAddress: String) throws -> String? {
        var query = baseQuery(for: emailAddress)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw StoreError.unhandledStatus(status)
        }

        guard
            let data = item as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            throw StoreError.invalidPassword
        }

        return password
    }

    func deleteAppPassword(for emailAddress: String) throws {
        let status = SecItemDelete(baseQuery(for: emailAddress) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for emailAddress: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
    }
}
