//
//  EmailProvider.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

enum EmailProvider: String, CaseIterable, Codable, Identifiable {
    case qq
    case netease163
    case gmail
    case custom

    var id: String {
        rawValue
    }

    static var selectableProviders: [EmailProvider] {
        [.netease163, .qq, .gmail]
    }

    static func detect(from emailAddress: String) -> EmailProvider {
        let normalized = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasSuffix("@qq.com") {
            return .qq
        }

        if normalized.hasSuffix("@163.com") {
            return .netease163
        }

        if normalized.hasSuffix("@gmail.com") {
            return .gmail
        }

        return .custom
    }

    var displayName: String {
        switch self {
        case .qq:
            "QQ 邮箱"
        case .netease163:
            "163 邮箱"
        case .gmail:
            "Gmail"
        case .custom:
            "自定义邮箱"
        }
    }

    var emailDomain: String? {
        switch self {
        case .qq:
            "qq.com"
        case .netease163:
            "163.com"
        case .gmail:
            "gmail.com"
        case .custom:
            nil
        }
    }

    var emailSuffix: String {
        emailDomain.map { "@\($0)" } ?? ""
    }

    func localPart(from emailAddress: String) -> String {
        let normalized = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let emailDomain, normalized.hasSuffix("@\(emailDomain)") else {
            return normalized
        }

        return String(normalized.dropLast(emailDomain.count + 1))
    }

    var systemImageName: String {
        switch self {
        case .qq, .netease163, .gmail:
            "checkmark.seal"
        case .custom:
            "questionmark.circle"
        }
    }

    var imapConfiguration: IMAPServerConfiguration? {
        switch self {
        case .qq:
            IMAPServerConfiguration(host: "imap.qq.com", port: 993, usesTLS: true)
        case .netease163:
            IMAPServerConfiguration(host: "imap.163.com", port: 993, usesTLS: true)
        case .gmail:
            IMAPServerConfiguration(host: "imap.gmail.com", port: 993, usesTLS: true)
        case .custom:
            nil
        }
    }
}
