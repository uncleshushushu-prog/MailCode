//
//  MailProviderClient.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

protocol MailProviderClient {
    func connect(account: EmailAccount, appPassword: String) async throws
    func testConnection(account: EmailAccount, appPassword: String) async throws
    func getCurrentMailboxCheckpoint(account: EmailAccount, appPassword: String) async throws -> MailboxCheckpoint
    func fetchNewMessages(
        account: EmailAccount,
        appPassword: String,
        after checkpoint: MailboxCheckpoint
    ) async throws -> [EmailMessage]
}

enum MailProviderClientError: Error, Equatable {
    case unsupportedProvider(EmailProvider)
    case missingCredential
    case invalidCredential
    case imapNotEnabled
    case networkUnavailable
    case timeout
    case tlsFailed
    case unsafeLogin
    case notImplemented
    case missingMailboxCheckpoint
    case underlying(String)

    var userMessage: String {
        switch self {
        case .unsupportedProvider:
            "暂不支持该邮箱服务商。"
        case .missingCredential:
            "请输入邮箱授权码或应用专用密码。"
        case .invalidCredential:
            "连接失败，请检查邮箱授权码是否正确。"
        case .imapNotEnabled:
            "连接失败，请确认该邮箱已开启 IMAP。"
        case .networkUnavailable:
            "网络不可用，请稍后重试。"
        case .timeout:
            "连接超时，请稍后重试。"
        case .tlsFailed:
            "安全连接失败，请稍后重试。"
        case .unsafeLogin:
            "邮箱服务商拦截了本次 IMAP 登录环境，请稍后重试，或按服务商提示联系客服处理。"
        case .notImplemented:
            "IMAP 连接模块尚未接入，暂时无法测试连接。"
        case .missingMailboxCheckpoint:
            "无法读取邮箱当前位置，请重新点击等待验证码；本次不会回扫历史邮件。"
        case .underlying:
            "连接失败，请检查邮箱授权码是否正确，并确认该邮箱已开启 IMAP。"
        }
    }
}
