//
//  AppModel.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Combine
import Foundation

struct ManualReviewEmail: Identifiable, Equatable {
    var id: String
    var sourceEmail: String
    var sender: String
    var subject: String
    var receivedAt: Date
    var bodyText: String
    var debugSummary: String
}

final class AppModel: ObservableObject {
    @Published var accountDraft = AccountDraft()
    @Published var listeningStatus: ListeningStatus = .notConfigured
    @Published var latestCode: VerificationCode?
    @Published var savedAccounts: [EmailAccount] = []
    @Published var savedAccount: EmailAccount?
    @Published var manualReviewEmails: [ManualReviewEmail] = []
    @Published var pollingDiagnostics: String?
    @Published private(set) var isListening = false
    @Published private(set) var listeningAccountIDs: Set<UUID> = []

    static let stablePollingMessage = "监听保持中，您可以最小化本窗口，收到验证码会有浮窗提醒。"

    private let floatingCodeWindowController = FloatingCodeWindowController()
    private let accountStore: EmailAccountStore
    private let credentialStore: KeychainCredentialStore
    private let mailClient: MailProviderClient
    private let verificationCodeExtractor = VerificationCodeExtractor()
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var extractionDebugSummaries: [UUID: String] = [:]
    private var ignoredManualReviewEmailIDs: Set<String> = []
    private var displayedVerificationKeys: Set<String> = []
    private var listeningStartedAtByAccountID: [UUID: Date] = [:]
    private var listeningStartUIDByAccountID: [UUID: UInt64] = [:]
    private var appPasswordCache: [String: String] = [:]
    private let pollingIntervalNanoseconds: UInt64 = 2_000_000_000
    private let maximumTransientPollingFailures = 5

    init(
        accountStore: EmailAccountStore = EmailAccountStore(),
        credentialStore: KeychainCredentialStore = KeychainCredentialStore(),
        mailClient: MailProviderClient = DirectIMAPClient()
    ) {
        self.accountStore = accountStore
        self.credentialStore = credentialStore
        self.mailClient = mailClient
        loadSavedAccounts()
        if !savedAccounts.isEmpty {
            resetCheckpointToCurrentMailbox()
        }
    }

    func testAndSaveAccountDraft() {
        guard accountDraft.canSave else {
            listeningStatus = .failed("请输入邮箱地址和授权码。")
            return
        }

        let shouldRestartListening = isListening
        let existingAccount = savedAccounts.first { $0.emailAddress == accountDraft.normalizedEmailAddress }
        let account = accountDraft.makeAccount(existingAccount: existingAccount)

        listeningStatus = .testingConnection

        Task {
            do {
                do {
                    try await mailClient.testConnection(account: account, appPassword: accountDraft.appPassword)
                } catch {
                    throw AccountConnectionTestError.login(error)
                }

                let checkpoint: MailboxCheckpoint
                do {
                    checkpoint = try await mailClient.getCurrentMailboxCheckpoint(account: account, appPassword: accountDraft.appPassword)
                } catch {
                    throw AccountConnectionTestError.mailboxCheckpoint(error)
                }

                guard checkpoint.searchStartUID != nil else {
                    throw AccountConnectionTestError.mailboxCheckpoint(MailProviderClientError.missingMailboxCheckpoint)
                }

                var connectedAccount = account
                connectedAccount.lastCheckpoint = checkpoint

                try accountStore.save(connectedAccount)
                try credentialStore.saveAppPassword(accountDraft.appPassword, for: connectedAccount.emailAddress)
                cacheAppPassword(accountDraft.appPassword, for: connectedAccount.emailAddress)

                upsertSavedAccount(connectedAccount)
                accountDraft = AccountDraft()
                if shouldRestartListening {
                    restartListeningForEnabledAccounts(reason: "\(connectedAccount.emailAddress) 连接测试成功，已重新启动全部准备就绪邮箱监听。")
                } else {
                    pollingDiagnostics = "\(connectedAccount.emailAddress) 连接测试成功，已记录当前邮箱位置。后续只检查新邮件。"
                    listeningStatus = .ready
                }
            } catch {
                pollingDiagnostics = nil
                listeningStatus = .failed(connectionTestMessage(for: error))
            }
        }
    }

    func startListeningForVerificationCode() {
        guard !savedAccounts.isEmpty else {
            listeningStatus = .failed("请先连接并保存邮箱。")
            return
        }

        let enabledAccounts = savedAccounts.filter(\.isEnabled)
        guard !enabledAccounts.isEmpty else {
            listeningStatus = .failed("请至少启用一个邮箱。")
            return
        }

        stopPollingTasks()
        beginListening(enabledAccounts: enabledAccounts, diagnostics: "监听已开始，正在检查 \(enabledAccounts.count) 个邮箱的新邮件。")
    }

    func stopListening() {
        stopPollingTasks()

        if savedAccounts.isEmpty {
            listeningStatus = .notConfigured
        } else if latestCode == nil {
            listeningStatus = .ready
        }

        pollingDiagnostics = "监听已停止。"
    }

    func setAccountEnabled(accountID: UUID, isEnabled: Bool) {
        guard var account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("没有找到这个邮箱。")
            return
        }

        let shouldRestartListening = isListening
        account.isEnabled = isEnabled
        account.updatedAt = .now

        do {
            try accountStore.save(account)
            upsertSavedAccount(account)

            if shouldRestartListening {
                let action = isEnabled ? "准备就绪" : "已停用"
                restartListeningForEnabledAccounts(reason: "\(account.emailAddress) \(action)，已重新启动全部准备就绪邮箱监听。")
            } else if isEnabled {
                listeningStatus = .ready
                pollingDiagnostics = "\(account.emailAddress) 准备就绪。"
            } else {
                stopListening(accountID: accountID)
                pollingDiagnostics = "\(account.emailAddress) 已停用。"
                listeningStatus = isListening ? .polling : (savedAccounts.contains(where: \.isEnabled) ? .ready : .notConfigured)
            }
        } catch {
            listeningStatus = .failed("保存邮箱状态失败。")
            pollingDiagnostics = nil
        }
    }

    func prepareAccountDraftForEditing(accountID: UUID) {
        guard let account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("没有找到这个邮箱。")
            pollingDiagnostics = nil
            return
        }

        let savedPassword = (try? loadCachedAppPassword(for: account.emailAddress)) ?? ""
        accountDraft = AccountDraft(account: account, appPassword: savedPassword)

        if savedPassword.isEmpty {
            pollingDiagnostics = "\(account.emailAddress) 未读取到已保存授权码，请重新输入后保存。"
        }
    }

    func testSavedAccountConnection(accountID: UUID) {
        guard let account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("没有找到这个邮箱。")
            pollingDiagnostics = nil
            return
        }

        let shouldKeepPollingStatus = isListening
        listeningStatus = .testingConnection
        pollingDiagnostics = "正在测试 \(account.emailAddress) 的连接和邮箱位置读取。"

        Task {
            do {
                guard let appPassword = try loadCachedAppPassword(for: account.emailAddress) else {
                    throw MailProviderClientError.missingCredential
                }

                do {
                    try await mailClient.testConnection(account: account, appPassword: appPassword)
                } catch {
                    throw AccountConnectionTestError.login(error)
                }

                let checkpoint: MailboxCheckpoint
                do {
                    checkpoint = try await mailClient.getCurrentMailboxCheckpoint(account: account, appPassword: appPassword)
                } catch {
                    throw AccountConnectionTestError.mailboxCheckpoint(error)
                }

                guard checkpoint.searchStartUID != nil else {
                    throw AccountConnectionTestError.mailboxCheckpoint(MailProviderClientError.missingMailboxCheckpoint)
                }

                var updatedAccount = account
                updatedAccount.lastCheckpoint = checkpoint
                updatedAccount.updatedAt = .now
                try accountStore.save(updatedAccount)
                upsertSavedAccount(updatedAccount)

                listeningStatus = shouldKeepPollingStatus ? .polling : .ready
                pollingDiagnostics = "\(updatedAccount.emailAddress) 测试连通成功，授权码有效，并已读取邮箱当前位置。"
            } catch {
                pollingDiagnostics = nil
                listeningStatus = .failed("\(account.emailAddress) 测试连通失败：\(connectionTestMessage(for: error))")
            }
        }
    }

    func deleteAccount(accountID: UUID) {
        guard let account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("没有找到这个邮箱。")
            return
        }

        stopListening(accountID: accountID)

        do {
            try accountStore.delete(emailAddress: account.emailAddress)
            try credentialStore.deleteAppPassword(for: account.emailAddress)
            removeCachedAppPassword(for: account.emailAddress)
            savedAccounts.removeAll { $0.id == accountID }
            savedAccount = savedAccounts.first
            extractionDebugSummaries[accountID] = nil
            latestCode = latestCode?.sourceEmail == account.emailAddress ? nil : latestCode
            listeningStatus = savedAccounts.isEmpty ? .notConfigured : .ready
            pollingDiagnostics = "\(account.emailAddress) 已删除。"
        } catch {
            listeningStatus = .failed("删除邮箱失败。")
            pollingDiagnostics = nil
        }
    }

    func resetCheckpointToCurrentMailbox() {
        guard !savedAccounts.isEmpty else {
            listeningStatus = .failed("请先连接并保存邮箱。")
            return
        }

        stopListening()
        resetCheckpointsToCurrentMailbox(accounts: savedAccounts)
    }

    func resetCheckpointToCurrentMailbox(accountID: UUID) {
        stopListening(accountID: accountID)

        guard let account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("请先连接并保存邮箱。")
            return
        }

        pollingDiagnostics = "正在重新记录当前邮箱位置。"

        Task {
            do {
                guard let appPassword = try loadCachedAppPassword(for: account.emailAddress) else {
                    throw MailProviderClientError.missingCredential
                }

                let checkpoint = try await mailClient.getCurrentMailboxCheckpoint(
                    account: account,
                    appPassword: appPassword
                )
                var updatedAccount = account
                updatedAccount.lastCheckpoint = checkpoint
                updatedAccount.updatedAt = .now

                try accountStore.save(updatedAccount)
                upsertSavedAccount(updatedAccount)
                listeningStatus = .ready
                pollingDiagnostics = "\(updatedAccount.emailAddress) 已重新记录当前邮箱位置。请重新点击“等待验证码”，再发送一封新的测试邮件。"
            } catch {
                pollingDiagnostics = nil
                listeningStatus = .failed(userMessage(for: error))
            }
        }
    }

    private func resetCheckpointsToCurrentMailbox(accounts: [EmailAccount]) {
        pollingDiagnostics = "正在重新记录所有邮箱当前位置。"

        Task {
            var updatedCount = 0
            var failedEmailAddresses: [String] = []

            for account in accounts {
                do {
                    guard let appPassword = try loadCachedAppPassword(for: account.emailAddress) else {
                        throw MailProviderClientError.missingCredential
                    }

                    let checkpoint = try await mailClient.getCurrentMailboxCheckpoint(
                        account: account,
                        appPassword: appPassword
                    )

                    var updatedAccount = account
                    updatedAccount.lastCheckpoint = checkpoint
                    updatedAccount.updatedAt = .now

                    try accountStore.save(updatedAccount)
                    upsertSavedAccount(updatedAccount)
                    updatedCount += 1
                } catch {
                    failedEmailAddresses.append(account.emailAddress)
                }
            }

            if failedEmailAddresses.isEmpty {
                listeningStatus = .ready
                pollingDiagnostics = "已重新记录 \(updatedCount) 个邮箱当前位置。"
            } else if updatedCount > 0 {
                listeningStatus = .ready
                pollingDiagnostics = "已重新记录 \(updatedCount) 个邮箱当前位置；\(failedEmailAddresses.joined(separator: "、")) 重置失败。"
            } else {
                listeningStatus = .failed("所有邮箱位置重置失败，请检查网络、授权码和 IMAP 状态。")
                pollingDiagnostics = nil
            }
        }
    }

    func showDemoVerificationCode() {
        let code = VerificationCode(
            code: "123456",
            sourceEmail: savedAccount?.emailAddress ?? savedAccounts.first?.emailAddress ?? "demo@mailcode.app",
            sender: "MailCode Test",
            subject: "您的验证码是 123456",
            receivedAt: .now,
            confidence: 1.0,
            expiresAt: Calendar.current.date(byAdding: .minute, value: 5, to: .now)
        )

        latestCode = code
        listeningStatus = .codeReceived
        floatingCodeWindowController.show(code: code)
    }

    func dismissManualReviewEmail(id: String) {
        manualReviewEmails.removeAll { $0.id == id }
    }

    private func loadSavedAccounts() {
        savedAccounts = accountStore.loadAccounts()
        savedAccount = savedAccounts.first
        listeningStatus = savedAccounts.isEmpty ? .notConfigured : .ready
    }

    private func loadCachedAppPassword(for emailAddress: String) throws -> String? {
        let cacheKey = credentialCacheKey(for: emailAddress)
        if let cachedPassword = appPasswordCache[cacheKey] {
            return cachedPassword
        }

        guard let appPassword = try credentialStore.loadAppPassword(for: emailAddress) else {
            return nil
        }

        appPasswordCache[cacheKey] = appPassword
        return appPassword
    }

    private func cacheAppPassword(_ appPassword: String, for emailAddress: String) {
        appPasswordCache[credentialCacheKey(for: emailAddress)] = appPassword
    }

    private func removeCachedAppPassword(for emailAddress: String) {
        appPasswordCache[credentialCacheKey(for: emailAddress)] = nil
    }

    private func credentialCacheKey(for emailAddress: String) -> String {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func pollForVerificationCode(accountID: UUID) async {
        var transientFailureCount = 0
        var shouldInitializeCheckpoint = true

        while !Task.isCancelled {
            let result: PollCheckResult
            do {
                if shouldInitializeCheckpoint {
                    try await initializeCheckpointForListeningStart(accountID: accountID)
                    shouldInitializeCheckpoint = false
                    result = .checkpointInitialized
                } else {
                    result = try await checkOnceForVerificationCode(accountID: accountID)
                }

                guard !Task.isCancelled, pollingTasks[accountID] != nil else {
                    return
                }

                switch result {
                case .codesFound(let count):
                    if count > 1 {
                        pollingDiagnostics = "已提取到 \(count) 个验证码，监听会继续保持。"
                    } else {
                        pollingDiagnostics = "已提取到验证码，监听会继续保持。"
                    }
                case .noNewMessages:
                    pollingDiagnostics = nil
                case .newMessagesWithoutCode(let count):
                    pollingDiagnostics = "本轮发现 \(count) 封新邮件，但没有提取到验证码。\(extractionDebugSummaries[accountID] ?? "暂无候选码调试信息。")"
                case .duplicateCodeIgnored:
                    pollingDiagnostics = "本轮发现的验证码已经弹出过，已自动忽略重复提醒。"
                case .checkpointInitialized:
                    pollingDiagnostics = nil
                case .uidValidityReset:
                    pollingDiagnostics = nil
                }
                transientFailureCount = 0
            } catch {
                guard !Task.isCancelled, pollingTasks[accountID] != nil else {
                    return
                }

                if isTransientPollingError(error), transientFailureCount < maximumTransientPollingFailures {
                    transientFailureCount += 1
                    pollingDiagnostics = "本轮连接暂时失败，正在保持 2 秒间隔重试（第 \(transientFailureCount)/\(maximumTransientPollingFailures) 次）。"
                    try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                    continue
                }

                pollingDiagnostics = nil
                pollingTasks[accountID] = nil
                markAccountNotListening(accountID)
                syncListeningState()
                let message = pollingFailureMessage(error, accountID: accountID)
                listeningStatus = isListening ? .polling : .failed(message)
                pollingDiagnostics = message
                return
            }

            if case .checkpointInitialized = result {
                continue
            }

            try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
        }
    }

    private func initializeCheckpointForListeningStart(accountID: UUID) async throws {
        guard var account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("请先连接并保存邮箱。")
            return
        }

        guard let appPassword = try loadCachedAppPassword(for: account.emailAddress) else {
            throw MailProviderClientError.missingCredential
        }

        var checkpoint: MailboxCheckpoint
        if let savedCheckpoint = account.lastCheckpoint, savedCheckpoint.searchStartUID != nil {
            checkpoint = savedCheckpoint
        } else {
            checkpoint = try await mailClient.getCurrentMailboxCheckpoint(
                account: account,
                appPassword: appPassword
            )
            account.lastCheckpoint = checkpoint
            account.updatedAt = .now
            try accountStore.save(account)
            upsertSavedAccount(account)
        }

        guard let searchStartUID = checkpoint.searchStartUID else {
            throw MailProviderClientError.missingMailboxCheckpoint
        }

        listeningStartedAtByAccountID[accountID] = checkpoint.recordedAt
        listeningStartUIDByAccountID[accountID] = searchStartUID
    }

    private func isTransientPollingError(_ error: Error) -> Bool {
        guard let error = error as? MailProviderClientError else {
            return false
        }

        switch error {
        case .networkUnavailable, .timeout, .tlsFailed:
            return true
        case .invalidCredential, .imapNotEnabled, .unsupportedProvider, .missingCredential, .unsafeLogin, .notImplemented, .missingMailboxCheckpoint, .underlying:
            return false
        }
    }

    private func checkOnceForVerificationCode(accountID: UUID) async throws -> PollCheckResult {
        guard var account = savedAccounts.first(where: { $0.id == accountID }) else {
            listeningStatus = .failed("请先连接并保存邮箱。")
            return .newMessagesWithoutCode(0)
        }

        guard let appPassword = try loadCachedAppPassword(for: account.emailAddress) else {
            throw MailProviderClientError.missingCredential
        }

        guard let checkpoint = account.lastCheckpoint else {
            account.lastCheckpoint = try await mailClient.getCurrentMailboxCheckpoint(
                account: account,
                appPassword: appPassword
            )
            account.updatedAt = .now
            try accountStore.save(account)
            upsertSavedAccount(account)
            return .checkpointInitialized
        }

        let currentCheckpoint = try await mailClient.getCurrentMailboxCheckpoint(
            account: account,
            appPassword: appPassword
        )

        if checkpoint.uidValidity != currentCheckpoint.uidValidity {
            account.lastCheckpoint = currentCheckpoint
            account.updatedAt = .now
            try accountStore.save(account)
            upsertSavedAccount(account)
            return .uidValidityReset
        }

        if
            let searchStartUID = checkpoint.searchStartUID,
            let currentUIDNext = currentCheckpoint.uidNext,
            currentUIDNext <= searchStartUID
        {
            return .noNewMessages
        }

        let messages = try await mailClient.fetchNewMessages(
            account: account,
            appPassword: appPassword,
            after: checkpoint
        )

        updateCheckpointIfNeeded(for: account, currentCheckpoint: currentCheckpoint, messages: messages)

        let messagesToInspect = messages.filter { message in
            isMessageEligibleForCurrentListeningWindow(message, accountID: accountID)
                && !ignoredManualReviewEmailIDs.contains(manualReviewEmailID(accountID: accountID, message: message))
        }

        guard !messagesToInspect.isEmpty else {
            return .noNewMessages
        }

        var foundDuplicateCode = false
        var freshCodes: [VerificationCode] = []

        for message in messagesToInspect.reversed() {
            guard let extractedCode = code(from: message, account: account) else {
                continue
            }

            let dedupKey = verificationDedupKey(for: extractedCode)
            if displayedVerificationKeys.contains(dedupKey) {
                foundDuplicateCode = true
                continue
            }

            displayedVerificationKeys.insert(dedupKey)
            freshCodes.append(extractedCode)
        }

        guard !freshCodes.isEmpty else {
            if foundDuplicateCode {
                return .duplicateCodeIgnored
            }

            addManualReviewEmails(messagesToInspect, account: account, accountID: accountID)
            extractionDebugSummaries[accountID] = messagesToInspect
                .reversed()
                .map { extractionDebugSummary(from: $0, account: account) }
                .first
            return .newMessagesWithoutCode(messagesToInspect.count)
        }

        extractionDebugSummaries[accountID] = nil
        for code in freshCodes.reversed() {
            latestCode = code
            floatingCodeWindowController.show(code: code)
        }
        listeningStatus = .codeReceived
        return .codesFound(freshCodes.count)
    }

    private func updateCheckpointIfNeeded(
        for account: EmailAccount,
        currentCheckpoint: MailboxCheckpoint,
        messages: [EmailMessage]
    ) {
        guard let latestUID = messages.map(\.uid).max() else {
            return
        }

        var updatedAccount = account
        updatedAccount.lastCheckpoint = MailboxCheckpoint(
            uidValidity: currentCheckpoint.uidValidity,
            latestUID: latestUID,
            uidNext: currentCheckpoint.uidNext,
            recordedAt: .now
        )
        updatedAccount.updatedAt = .now

        try? accountStore.save(updatedAccount)
        upsertSavedAccount(updatedAccount)
    }

    private func isMessageEligibleForCurrentListeningWindow(_ message: EmailMessage, accountID: UUID) -> Bool {
        guard
            let listeningStartedAt = listeningStartedAtByAccountID[accountID],
            let listeningStartUID = listeningStartUIDByAccountID[accountID]
        else {
            return false
        }

        guard message.uid >= listeningStartUID else {
            return false
        }

        guard message.hasParsedReceivedAt else {
            return false
        }

        return message.receivedAt >= listeningStartedAt.addingTimeInterval(-5)
    }

    private func upsertSavedAccount(_ account: EmailAccount) {
        if let index = savedAccounts.firstIndex(where: { $0.emailAddress == account.emailAddress }) {
            savedAccounts[index] = account
        } else {
            savedAccounts.append(account)
        }

        savedAccounts.sort { $0.emailAddress < $1.emailAddress }
        savedAccount = savedAccounts.first
    }

    private func stopListening(accountID: UUID) {
        pollingTasks[accountID]?.cancel()
        pollingTasks[accountID] = nil
        markAccountNotListening(accountID)
        listeningStartedAtByAccountID[accountID] = nil
        listeningStartUIDByAccountID[accountID] = nil
        syncListeningState()
    }

    private func stopPollingTasks() {
        pollingTasks.values.forEach { $0.cancel() }
        pollingTasks.removeAll()
        listeningAccountIDs = []
        listeningStartedAtByAccountID.removeAll()
        listeningStartUIDByAccountID.removeAll()
        syncListeningState()
    }

    private func restartListeningForEnabledAccounts(reason: String) {
        let enabledAccounts = savedAccounts.filter(\.isEnabled)
        stopPollingTasks()

        guard !enabledAccounts.isEmpty else {
            listeningStatus = savedAccounts.isEmpty ? .notConfigured : .ready
            pollingDiagnostics = reason
            return
        }

        beginListening(enabledAccounts: enabledAccounts, diagnostics: reason)
    }

    private func beginListening(enabledAccounts: [EmailAccount], diagnostics: String) {
        listeningStatus = .polling
        pollingDiagnostics = diagnostics
        listeningAccountIDs = Set(enabledAccounts.map(\.id))

        for account in enabledAccounts {
            startPollingIfNeeded(for: account)
        }

        syncListeningState()
    }

    private func startPollingIfNeeded(for account: EmailAccount) {
        guard account.isEnabled, pollingTasks[account.id] == nil else {
            return
        }

        pollingTasks[account.id] = Task { [weak self] in
            await self?.pollForVerificationCode(accountID: account.id)
        }
        markAccountListening(account.id)
        syncListeningState()
    }

    private func markAccountListening(_ accountID: UUID) {
        var updatedIDs = listeningAccountIDs
        updatedIDs.insert(accountID)
        listeningAccountIDs = updatedIDs
    }

    private func markAccountNotListening(_ accountID: UUID) {
        var updatedIDs = listeningAccountIDs
        updatedIDs.remove(accountID)
        listeningAccountIDs = updatedIDs
    }

    private func syncListeningState() {
        isListening = !pollingTasks.isEmpty
    }

    private func code(from message: EmailMessage, account: EmailAccount) -> VerificationCode? {
        verificationCodeExtractor.extract(
            from: VerificationCodeExtractor.Input(
                sourceEmail: account.emailAddress,
                sender: message.sender,
                subject: message.subject,
                plainTextBody: message.plainTextBody,
                htmlTextBody: message.htmlTextBody,
                receivedAt: message.receivedAt
            )
        )
    }

    private func extractionDebugSummary(from message: EmailMessage, account: EmailAccount) -> String {
        verificationCodeExtractor.debugSummary(
            from: VerificationCodeExtractor.Input(
                sourceEmail: account.emailAddress,
                sender: message.sender,
                subject: message.subject,
                plainTextBody: message.plainTextBody,
                htmlTextBody: message.htmlTextBody,
                receivedAt: message.receivedAt
            )
        )
    }

    private func verificationDedupKey(for code: VerificationCode) -> String {
        [
            code.sourceEmail,
            code.sender,
            code.subject,
            code.code
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }

    private func addManualReviewEmails(_ messages: [EmailMessage], account: EmailAccount, accountID: UUID) {
        for message in messages {
            let id = manualReviewEmailID(accountID: accountID, message: message)
            ignoredManualReviewEmailIDs.insert(id)

            guard !manualReviewEmails.contains(where: { $0.id == id }) else {
                continue
            }

            manualReviewEmails.insert(
                ManualReviewEmail(
                    id: id,
                    sourceEmail: account.emailAddress,
                    sender: message.sender,
                    subject: message.subject.isEmpty ? "无主题" : message.subject,
                    receivedAt: message.receivedAt,
                    bodyText: manualReviewText(from: message),
                    debugSummary: extractionDebugSummary(from: message, account: account)
                ),
                at: 0
            )
        }
    }

    private func manualReviewEmailID(accountID: UUID, message: EmailMessage) -> String {
        "\(accountID.uuidString)-\(message.uid)"
    }

    private func manualReviewText(from message: EmailMessage) -> String {
        let body = message.plainTextBody ?? strippedHTML(message.htmlTextBody ?? "")
        return """
        From: \(message.sender)
        Subject: \(message.subject.isEmpty ? "无主题" : message.subject)

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func strippedHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func userMessage(for error: Error) -> String {
        if let mailError = error as? MailProviderClientError {
            return mailError.userMessage
        }

        return "连接失败，请检查邮箱授权码是否正确，并确认该邮箱已开启 IMAP。"
    }

    private func connectionTestMessage(for error: Error) -> String {
        if let error = error as? AccountConnectionTestError {
            switch error {
            case .login(let underlying):
                return "登录失败：\(detailedUserMessage(for: underlying))"
            case .mailboxCheckpoint(let underlying):
                return "登录成功，但读取邮箱位置失败：\(detailedUserMessage(for: underlying))"
            }
        }

        return detailedUserMessage(for: error)
    }

    private func detailedUserMessage(for error: Error) -> String {
        if let mailError = error as? MailProviderClientError {
            switch mailError {
            case .underlying(let details):
                return "服务器返回异常：\(sanitizedServerDetails(details))"
            default:
                return mailError.userMessage
            }
        }

        return "连接失败：\(sanitizedServerDetails(String(describing: error)))"
    }

    private func sanitizedServerDetails(_ details: String) -> String {
        let compact = details
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard compact.count > 220 else {
            return compact.isEmpty ? "无详细信息。" : compact
        }

        return String(compact.prefix(220)) + "..."
    }

    private func pollingFailureMessage(_ error: Error, accountID: UUID) -> String {
        let emailAddress = savedAccounts.first(where: { $0.id == accountID })?.emailAddress ?? "邮箱"
        return "\(emailAddress) 监听连接失败：\(detailedUserMessage(for: error))。请检查邮箱设置后重试；若确认配置无误，请联系开发者。"
    }
}

private enum PollCheckResult {
    case checkpointInitialized
    case uidValidityReset
    case noNewMessages
    case newMessagesWithoutCode(Int)
    case duplicateCodeIgnored
    case codesFound(Int)
}

private enum AccountConnectionTestError: Error {
    case login(Error)
    case mailboxCheckpoint(Error)
}

enum ListeningStatus {
    case notConfigured
    case testingConnection
    case ready
    case polling
    case codeReceived
    case noCodeFound
    case failed(String)

    var title: String {
        switch self {
        case .notConfigured:
            "尚未连接邮箱"
        case .testingConnection:
            "正在测试连接"
        case .ready:
            "已准备监听"
        case .polling:
            "正在等待新验证码"
        case .codeReceived:
            "已收到验证码"
        case .noCodeFound:
            "暂未发现验证码"
        case .failed:
            "连接异常"
        }
    }

    var message: String {
        switch self {
        case .notConfigured:
            "先添加邮箱并完成连接测试。"
        case .testingConnection:
            "正在验证账号，不会读取历史邮件。"
        case .ready:
            "连接成功后只会检查新的邮件。"
        case .polling:
            AppModel.stablePollingMessage
        case .codeReceived:
            "验证码已显示在悬浮窗中，监听会继续保持。"
        case .noCodeFound:
            "暂未发现新验证码邮件，监听会继续保持。"
        case .failed(let reason):
            reason
        }
    }

    var systemImageName: String {
        switch self {
        case .notConfigured:
            "envelope.badge"
        case .testingConnection:
            "hourglass"
        case .ready:
            "checkmark.circle"
        case .polling:
            "dot.radiowaves.left.and.right"
        case .codeReceived:
            "number.circle"
        case .noCodeFound:
            "clock.badge.questionmark"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var isBusy: Bool {
        switch self {
        case .testingConnection:
            true
        case .notConfigured, .ready, .polling, .codeReceived, .noCodeFound, .failed:
            false
        }
    }
}
