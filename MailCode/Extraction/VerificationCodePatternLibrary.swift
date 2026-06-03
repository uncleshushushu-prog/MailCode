//
//  VerificationCodePatternLibrary.swift
//  MailCode
//
//  Created by Codex on 2026/6/2.
//

import Foundation

struct VerificationCodePatternLibrary {
    static let `default` = VerificationCodePatternLibrary()

    let patterns: [VerificationCodePattern]

    init(patterns: [VerificationCodePattern] = VerificationCodePatternLibrary.defaultPatterns) {
        self.patterns = patterns.sorted { lhs, rhs in
            lhs.priority > rhs.priority
        }
    }

    private static let keywordPattern = [
        "verification code",
        "security code",
        "login code",
        "confirmation code",
        "auth code",
        "authentication code",
        "one-time password",
        "passcode",
        "otp",
        "pin",
        "code",
        "验证码",
        "校验码",
        "动态码",
        "一次性密码",
        "登录码",
        "确认码",
        "安全码",
        "认证码",
        "识别码",
        "短信码",
        "验证",
        "认证"
    ].map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")

    private static let defaultPatterns: [VerificationCodePattern] = [
        VerificationCodePattern(
            id: "contextual_alphanumeric",
            priority: 100,
            kind: .contextual,
            pattern: #"(?i)(?:\#(keywordPattern))(?:[\s:：.\-#=]|is|are|为|是|为：|是：){0,20}([A-Z0-9０-９]{4,16}|[0-9０-９](?:[\s\-]?[0-9０-９]){3,9})"#,
            normalizedLength: 4...16
        ),
        VerificationCodePattern(
            id: "numeric_strict",
            priority: 80,
            kind: .numeric,
            pattern: #"(?<![0-9０-９])([0-9０-９]{4,10})(?![0-9０-９])"#,
            normalizedLength: 4...10
        ),
        VerificationCodePattern(
            id: "numeric_separated",
            priority: 70,
            kind: .separatedNumeric,
            pattern: #"(?<![0-9０-９])([0-9０-９](?:[\s\-]?[0-9０-９]){3,9})(?![0-9０-９])"#,
            normalizedLength: 4...10
        ),
        VerificationCodePattern(
            id: "alphanumeric_strict",
            priority: 60,
            kind: .alphaNumeric,
            pattern: #"(?<![A-Za-z0-9])([A-Za-z0-9]{4,12})(?![A-Za-z0-9])"#,
            normalizedLength: 4...12
        ),
        VerificationCodePattern(
            id: "upper_alphanumeric_loose",
            priority: 40,
            kind: .looseUpperAlphaNumeric,
            pattern: #"(?<![A-Z0-9])([A-Z0-9]{5,16})(?![A-Z0-9])"#,
            normalizedLength: 5...16
        )
    ]
}
