//
//  VerificationCodeScorer.swift
//  MailCode
//
//  Created by Codex on 2026/6/2.
//

import Foundation

struct VerificationCodeScorer {
    struct Result {
        var candidate: VerificationCodeCandidate
        var score: Double
        var isExcluded: Bool
    }

    nonisolated func score(_ candidate: VerificationCodeCandidate) -> Result {
        if isExcluded(candidate) {
            return Result(candidate: candidate, score: 0, isExcluded: true)
        }

        var score = baseScore(for: candidate)
        score += lengthScore(for: candidate.code, kind: candidate.pattern.kind)

        if Self.containsKeyword(in: candidate.context) {
            score += 0.30
        }

        switch candidate.source {
        case .subject:
            score += 0.22
        case .plainTextBody, .htmlTextBody:
            score += candidate.location < max(candidate.textLength / 2, 1) ? 0.12 : 0.05
        }

        if Self.containsExpirationHint(in: candidate.context) {
            score += 0.10
        }

        return Result(candidate: candidate, score: score, isExcluded: false)
    }

    private nonisolated func baseScore(for candidate: VerificationCodeCandidate) -> Double {
        switch candidate.pattern.kind {
        case .contextual:
            return 0.50
        case .numeric:
            return 0.25
        case .separatedNumeric:
            return 0.30
        case .alphaNumeric:
            return 0.18
        case .looseUpperAlphaNumeric:
            return 0.12
        }
    }

    private nonisolated func lengthScore(for code: String, kind: VerificationCodePattern.Kind) -> Double {
        let hasLetter = code.contains { $0.isLetter }
        let hasNumber = code.contains { $0.isNumber }

        if hasLetter && hasNumber {
            switch code.count {
            case 6...10:
                return 0.25
            case 4...5, 11...16:
                return 0.18
            default:
                return 0.08
            }
        }

        if hasLetter && !hasNumber {
            switch kind {
            case .contextual:
                return 0.02
            case .numeric, .separatedNumeric, .alphaNumeric, .looseUpperAlphaNumeric:
                return -0.30
            }
        }

        switch code.count {
        case 6:
            return 0.28
        case 4, 5, 8:
            return 0.18
        case 7, 9, 10:
            return 0.12
        default:
            return 0.04
        }
    }

    private nonisolated func isExcluded(_ candidate: VerificationCodeCandidate) -> Bool {
        let normalizedContext = candidate.context.lowercased()

        if looksLikePlaceholder(candidate.code) || looksLikeCSSHexColor(candidate.code, context: normalizedContext) {
            return true
        }

        if looksLikeInstructionWord(candidate.code) {
            return true
        }

        if Self.containsKeyword(in: normalizedContext) {
            return false
        }

        if candidate.code.count >= 7,
           Self.containsAny(normalizedContext, ["手机", "电话", "phone", "tel", "mobile"]) {
            return true
        }

        if looksLikeDateOrTime(candidate.code, context: normalizedContext) {
            return true
        }

        if Self.containsAny(normalizedContext, ["金额", "¥", "$", "rmb", "usd", "price", "amount"]) {
            return true
        }

        if Self.containsAny(normalizedContext, ["订单", "流水", "发票", "invoice", "order", "ticket", "serial"]) {
            return true
        }

        switch candidate.pattern.kind {
        case .alphaNumeric, .looseUpperAlphaNumeric:
            if Self.containsAny(normalizedContext, ["http", "href=", "src=", "token=", "utm_", "unsubscribe"]) {
                return true
            }
        case .contextual, .numeric, .separatedNumeric:
            break
        }

        return false
    }

    private nonisolated func looksLikePlaceholder(_ code: String) -> Bool {
        code.allSatisfy { $0 == "0" }
    }

    private nonisolated func looksLikeCSSHexColor(_ code: String, context: String) -> Bool {
        guard (3...8).contains(code.count) else {
            return false
        }

        return context.contains("#\(code.lowercased())")
    }

    private nonisolated func looksLikeInstructionWord(_ code: String) -> Bool {
        let normalized = code.lowercased()
        guard normalized.allSatisfy({ $0.isLetter }) else {
            return false
        }

        let words = [
            "valid",
            "with",
            "this",
            "that",
            "your",
            "from",
            "have",
            "will",
            "sent",
            "mail",
            "email",
            "verify",
            "login",
            "code",
            "token",
            "expires",
            "expire",
            "minutes",
            "minute",
            "security",
            "confirm",
            "continue",
            "account"
        ]

        return words.contains(normalized)
    }

    private nonisolated func looksLikeDateOrTime(_ code: String, context: String) -> Bool {
        if code.count == 4,
           let year = Int(code),
           (1900...2099).contains(year) {
            return true
        }

        return matches(#"\d{1,2}:\d{2}"#, in: context)
            || matches(#"\d{4}[-/年]\d{1,2}"#, in: context)
            || matches(#"\d{1,2}[-/月]\d{1,2}"#, in: context)
            || matches(#"\b(?:date|time)\b"#, in: context)
    }

    private nonisolated func matches(_ pattern: String, in text: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex?.firstMatch(in: text, range: range) != nil
    }

    nonisolated static func containsKeyword(in text: String) -> Bool {
        let normalized = text.lowercased()
        let keywords = [
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
            "verification code",
            "one-time password",
            "security code",
            "login code",
            "confirmation code",
            "authentication code",
            "auth code",
            "passcode",
            "otp",
            "pin",
            "code"
        ]

        return keywords.contains { normalized.contains($0) }
    }

    nonisolated static func containsExpirationHint(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("分钟")
            || normalized.contains("有效")
            || normalized.contains("expires")
            || normalized.contains("valid")
            || normalized.contains("minutes")
            || normalized.contains("mins")
    }

    private nonisolated static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }
}
