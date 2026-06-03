//
//  EmailAccount.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct EmailAccount: Identifiable, Codable, Equatable {
    var id: UUID
    var emailAddress: String
    var provider: EmailProvider
    var isEnabled: Bool
    var lastCheckpoint: MailboxCheckpoint?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        emailAddress: String,
        provider: EmailProvider,
        isEnabled: Bool = true,
        lastCheckpoint: MailboxCheckpoint? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.emailAddress = emailAddress
        self.provider = provider
        self.isEnabled = isEnabled
        self.lastCheckpoint = lastCheckpoint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
