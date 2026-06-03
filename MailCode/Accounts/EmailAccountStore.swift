//
//  EmailAccountStore.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct EmailAccountStore {
    enum StoreError: Error {
        case encodingFailed
    }

    private let defaults: UserDefaults
    private let legacyAccountKey = "mailcode.emailAccount"
    private let accountsKey = "mailcode.emailAccounts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAccounts() -> [EmailAccount] {
        if let data = defaults.data(forKey: accountsKey),
           let accounts = try? JSONDecoder().decode([EmailAccount].self, from: data) {
            return accounts.sortedByEmailAddress()
        }

        guard let legacyAccount = loadLegacyAccount() else {
            return []
        }

        try? saveAccounts([legacyAccount])
        defaults.removeObject(forKey: legacyAccountKey)
        return [legacyAccount]
    }

    func loadAccount() -> EmailAccount? {
        loadAccounts().first
    }

    func save(_ account: EmailAccount) throws {
        var accounts = loadAccounts()
        if let index = accounts.firstIndex(where: { $0.emailAddress == account.emailAddress }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }

        try saveAccounts(accounts)
    }

    func saveAccounts(_ accounts: [EmailAccount]) throws {
        guard let data = try? JSONEncoder().encode(accounts.sortedByEmailAddress()) else {
            throw StoreError.encodingFailed
        }

        defaults.set(data, forKey: accountsKey)
    }

    func clear() {
        defaults.removeObject(forKey: accountsKey)
        defaults.removeObject(forKey: legacyAccountKey)
    }

    func delete(emailAddress: String) throws {
        let normalizedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accounts = loadAccounts().filter { $0.emailAddress != normalizedEmail }
        try saveAccounts(accounts)
    }

    private func loadLegacyAccount() -> EmailAccount? {
        guard let data = defaults.data(forKey: legacyAccountKey) else {
            return nil
        }

        return try? JSONDecoder().decode(EmailAccount.self, from: data)
    }
}

private extension Array where Element == EmailAccount {
    func sortedByEmailAddress() -> [EmailAccount] {
        sorted { lhs, rhs in
            lhs.emailAddress < rhs.emailAddress
        }
    }
}
