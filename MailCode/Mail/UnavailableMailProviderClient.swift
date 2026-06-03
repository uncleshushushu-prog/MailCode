//
//  UnavailableMailProviderClient.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct UnavailableMailProviderClient: MailProviderClient {
    func connect(account: EmailAccount, appPassword: String) async throws {
        throw MailProviderClientError.notImplemented
    }

    func testConnection(account: EmailAccount, appPassword: String) async throws {
        throw MailProviderClientError.notImplemented
    }

    func getCurrentMailboxCheckpoint(account: EmailAccount, appPassword: String) async throws -> MailboxCheckpoint {
        throw MailProviderClientError.notImplemented
    }

    func fetchNewMessages(
        account: EmailAccount,
        appPassword: String,
        after checkpoint: MailboxCheckpoint
    ) async throws -> [EmailMessage] {
        throw MailProviderClientError.notImplemented
    }
}
