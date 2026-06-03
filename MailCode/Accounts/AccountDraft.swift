//
//  AccountDraft.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct AccountDraft {
    var emailLocalPart = ""
    var provider: EmailProvider = .netease163
    var appPassword = ""

    var detectedProvider: EmailProvider {
        provider
    }

    private var normalizedEmailLocalPart: String {
        emailLocalPart
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "@", maxSplits: 1)
            .first
            .map(String.init) ?? ""
    }

    var normalizedEmailAddress: String {
        let localPart = normalizedEmailLocalPart

        if let emailDomain = provider.emailDomain {
            return "\(localPart)@\(emailDomain)"
        }

        return localPart
    }

    var canSave: Bool {
        !normalizedEmailLocalPart.isEmpty && !appPassword.isEmpty
    }

    init(emailAddress: String = "", provider: EmailProvider? = nil, appPassword: String = "") {
        let detectedProvider = provider ?? EmailProvider.detect(from: emailAddress)
        self.provider = detectedProvider == .custom ? .netease163 : detectedProvider
        self.emailLocalPart = self.provider.localPart(from: emailAddress)
        self.appPassword = appPassword
    }

    init(account: EmailAccount, appPassword: String = "") {
        self.provider = account.provider == .custom ? EmailProvider.detect(from: account.emailAddress) : account.provider
        if self.provider == .custom {
            self.provider = .netease163
        }
        self.emailLocalPart = self.provider.localPart(from: account.emailAddress)
        self.appPassword = appPassword
    }

    func makeAccount(existingAccount: EmailAccount? = nil) -> EmailAccount {
        let now = Date()

        return EmailAccount(
            id: existingAccount?.id ?? UUID(),
            emailAddress: normalizedEmailAddress,
            provider: provider,
            isEnabled: true,
            lastCheckpoint: existingAccount?.lastCheckpoint,
            createdAt: existingAccount?.createdAt ?? now,
            updatedAt: now
        )
    }
}
