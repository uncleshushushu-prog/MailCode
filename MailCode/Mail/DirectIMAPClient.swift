//
//  DirectIMAPClient.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation
import Network

struct DirectIMAPClient: MailProviderClient {
    func connect(account: EmailAccount, appPassword: String) async throws {
        let session = try await login(account: account, appPassword: appPassword)
        defer { Task { await session.connection.close() } }
        _ = try? await session.connection.send(command: "LOGOUT", tag: session.nextTag())
    }

    func testConnection(account: EmailAccount, appPassword: String) async throws {
        try await connect(account: account, appPassword: appPassword)
    }

    func getCurrentMailboxCheckpoint(account: EmailAccount, appPassword: String) async throws -> MailboxCheckpoint {
        let session = try await login(account: account, appPassword: appPassword)
        defer { Task { await session.connection.close() } }

        let tag = session.nextTag()
        let response = try await session.connection.send(command: #"STATUS "INBOX" (UIDNEXT UIDVALIDITY)"#, tag: tag)
        guard IMAPResponseParser.statusIndicatesSuccess(response, tag: tag) else {
            throw IMAPResponseParser.classifyFailure(response)
        }

        let statusCheckpoint = IMAPResponseParser.checkpoint(from: response)
        guard statusCheckpoint.searchStartUID == nil else {
            _ = try? await session.connection.send(command: "LOGOUT", tag: session.nextTag())
            return statusCheckpoint
        }

        let examineCheckpoint = try await getMailboxCheckpointFromExamine(session: session)
        _ = try? await session.connection.send(command: "LOGOUT", tag: session.nextTag())
        return examineCheckpoint
    }

    func fetchNewMessages(
        account: EmailAccount,
        appPassword: String,
        after checkpoint: MailboxCheckpoint
    ) async throws -> [EmailMessage] {
        let session = try await login(account: account, appPassword: appPassword)
        defer { Task { await session.connection.close() } }

        let examineTag = session.nextTag()
        let examineResponse = try await session.connection.send(command: #"EXAMINE "INBOX""#, tag: examineTag)
        guard IMAPResponseParser.statusIndicatesSuccess(examineResponse, tag: examineTag) else {
            throw IMAPResponseParser.classifyFailure(examineResponse)
        }

        guard let startingUID = checkpoint.searchStartUID else {
            throw MailProviderClientError.missingMailboxCheckpoint
        }

        let searchTag = session.nextTag()
        let searchResponse = try await session.connection.send(command: "UID SEARCH UID \(startingUID):*", tag: searchTag)
        guard IMAPResponseParser.statusIndicatesSuccess(searchResponse, tag: searchTag) else {
            throw IMAPResponseParser.classifyFailure(searchResponse)
        }

        let uids = IMAPResponseParser.searchUIDs(from: searchResponse)
        guard !uids.isEmpty else {
            _ = try? await session.connection.send(command: "LOGOUT", tag: session.nextTag())
            return []
        }

        var messages: [EmailMessage] = []
        for uid in uids {
            let fetchTag = session.nextTag()
            let fetchResponse = try await session.connection.send(
                command: "UID FETCH \(uid) (UID INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)] BODY.PEEK[TEXT])",
                tag: fetchTag
            )

            guard IMAPResponseParser.statusIndicatesSuccess(fetchResponse, tag: fetchTag) else {
                throw IMAPResponseParser.classifyFailure(fetchResponse)
            }

            if let message = IMAPResponseParser.emailMessage(from: fetchResponse, fallbackUID: uid) {
                messages.append(message)
            }
        }

        _ = try? await session.connection.send(command: "LOGOUT", tag: session.nextTag())
        return messages
    }

    private func login(account: EmailAccount, appPassword: String) async throws -> IMAPSession {
        guard !appPassword.isEmpty else {
            throw MailProviderClientError.missingCredential
        }

        guard let configuration = account.provider.imapConfiguration else {
            throw MailProviderClientError.unsupportedProvider(account.provider)
        }

        let connection = IMAPConnection(configuration: configuration)

        do {
            try await connection.open()
            let greeting = try await connection.readGreeting()
            guard greeting.uppercased().contains("OK") else {
                throw MailProviderClientError.underlying(greeting)
            }

            let session = IMAPSession(connection: connection)
            let tag = session.nextTag()
            let response = try await connection.send(
                command: "LOGIN \(IMAPCommand.quote(account.emailAddress)) \(IMAPCommand.quote(appPassword))",
                tag: tag
            )

            guard IMAPResponseParser.statusIndicatesSuccess(response, tag: tag) else {
                throw IMAPResponseParser.classifyFailure(response)
            }

            if account.provider == .netease163 {
                try await sendClientID(on: session)
            }

            return session
        } catch let error as MailProviderClientError {
            await connection.close()
            throw error
        } catch {
            await connection.close()
            throw mapConnectionError(error)
        }
    }

    private func sendClientID(on session: IMAPSession) async throws {
        let tag = session.nextTag()
        let response = try await session.connection.send(
            command: IMAPCommand.id([
                ("name", "MailCode"),
                ("version", "1.0"),
                ("vendor", "MailCode"),
                ("support-email", "support@mailcode.local")
            ]),
            tag: tag
        )

        guard IMAPResponseParser.statusIndicatesSuccess(response, tag: tag) else {
            throw IMAPResponseParser.classifyFailure(response)
        }
    }

    private func getMailboxCheckpointFromExamine(session: IMAPSession) async throws -> MailboxCheckpoint {
        let tag = session.nextTag()
        let response = try await session.connection.send(command: #"EXAMINE "INBOX""#, tag: tag)
        guard IMAPResponseParser.statusIndicatesSuccess(response, tag: tag) else {
            throw IMAPResponseParser.classifyFailure(response)
        }

        let checkpoint = IMAPResponseParser.checkpoint(from: response)
        guard checkpoint.searchStartUID == nil else {
            return checkpoint
        }

        return try await getMailboxCheckpointFromUIDSearchAll(
            session: session,
            uidValidity: checkpoint.uidValidity
        )
    }

    private func getMailboxCheckpointFromUIDSearchAll(session: IMAPSession, uidValidity: UInt64?) async throws -> MailboxCheckpoint {
        let tag = session.nextTag()
        let response = try await session.connection.send(command: "UID SEARCH ALL", tag: tag)
        guard IMAPResponseParser.statusIndicatesSuccess(response, tag: tag) else {
            throw IMAPResponseParser.classifyFailure(response)
        }

        let uids = IMAPResponseParser.searchUIDs(from: response)
        return MailboxCheckpoint(
            uidValidity: uidValidity,
            latestUID: uids.max(),
            uidNext: uids.isEmpty ? 1 : nil,
            recordedAt: .now
        )
    }

    private func mapConnectionError(_ error: Error) -> MailProviderClientError {
        if let error = error as? MailProviderClientError {
            return error
        }

        return .underlying(String(describing: error))
    }
}

final class IMAPSession {
    let connection: IMAPConnection
    private var tagIndex = 0

    init(connection: IMAPConnection) {
        self.connection = connection
    }

    func nextTag() -> String {
        tagIndex += 1
        return String(format: "A%03d", tagIndex)
    }
}
