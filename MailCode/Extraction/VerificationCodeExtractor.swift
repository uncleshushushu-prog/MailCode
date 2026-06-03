//
//  VerificationCodeExtractor.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import AppKit
import Foundation

struct VerificationCodeExtractor {
    struct Input {
        var sourceEmail: String
        var sender: String
        var subject: String
        var plainTextBody: String?
        var htmlTextBody: String?
        var receivedAt: Date
    }

    private struct KeywordMatch {
        var id: String
        var range: NSRange
    }

    private struct CandidateCode {
        var rawCode: String
        var normalizedCode: String
        var range: NSRange
        var keyword: KeywordMatch
        var distance: Int
    }

    init() {}

    nonisolated func extract(from input: Input) -> VerificationCode? {
        let cleanedBody = cleanedBody(from: input)
        let searchText = normalizedSearchText(subject: input.subject, body: cleanedBody)

        guard let match = bestMatch(in: searchText) else {
            return nil
        }

        return VerificationCode(
            code: match.normalizedCode,
            sourceEmail: input.sourceEmail,
            sender: input.sender,
            subject: input.subject,
            receivedAt: input.receivedAt,
            confidence: confidence(for: match),
            expiresAt: Self.expirationDate(from: searchText, receivedAt: input.receivedAt)
        )
    }

    nonisolated func debugSummary(from input: Input) -> String {
        let cleanedBody = cleanedBody(from: input)
        let searchText = normalizedSearchText(subject: input.subject, body: cleanedBody)
        let subjectLength = input.subject.count
        let bodyLength = cleanedBody.count

        guard let match = bestMatch(in: searchText) else {
            return "未扫描到可用候选码。主题 \(subjectLength) 字，清洗正文 \(bodyLength) 字；未找到关键词附近的验证码候选。"
        }

        let context = (searchText as NSString).substring(with: expandedContextRange(around: match.range, in: (searchText as NSString).length))
        return "候选码：\(match.normalizedCode)（关键词 \(match.keyword.id)，距离 \(match.distance)，置信度 \(String(format: "%.2f", confidence(for: match)))，上下文：\(sanitizedContext(context))）"
    }

    private nonisolated func cleanedBody(from input: Input) -> String {
        let body = input.plainTextBody ?? input.htmlTextBody ?? ""
        let text = Self.containsHTML(in: body) ? Self.htmlToText(body) : body
        return Self.collapseWhitespace(text)
    }

    private nonisolated func normalizedSearchText(subject: String, body: String) -> String {
        Self.collapseWhitespace("\(subject) \(body)")
    }

    private nonisolated func bestMatch(in text: String) -> CandidateCode? {
        let keywords = keywordMatches(in: text)
        guard !keywords.isEmpty else {
            return nil
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let candidateExpression = Self.candidateExpression

        return candidateExpression
            .matches(in: text, range: fullRange)
            .compactMap { match -> CandidateCode? in
                let range = match.range
                let rawCode = nsText.substring(with: range)
                let validationContextRange = validationContextRange(around: range, in: nsText.length)
                let validationContext = nsText.substring(with: validationContextRange)

                guard let code = normalizedCode(from: rawCode), isAcceptable(rawCode: rawCode, code: code, context: validationContext) else {
                    return nil
                }

                guard let nearestKeyword = nearestKeyword(to: range, keywords: keywords) else {
                    return nil
                }

                let distance = distanceBetween(range, nearestKeyword.range)
                guard distance <= 100 else {
                    return nil
                }

                return CandidateCode(
                    rawCode: rawCode,
                    normalizedCode: code,
                    range: range,
                    keyword: nearestKeyword,
                    distance: distance
                )
            }
            .min { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.range.location < rhs.range.location
                }

                return lhs.distance < rhs.distance
            }
    }

    private nonisolated func normalizedCode(from rawCode: String) -> String? {
        let normalized = rawCode
            .map(Self.normalizeCharacter)
            .filter { !$0.isWhitespace && $0 != "-" }
            .map(String.init)
            .joined()
            .uppercased()

        guard (4...12).contains(normalized.count),
              normalized.allSatisfy({ $0.isASCIIAlphanumeric }) else {
            return nil
        }

        return normalized
    }

    private nonisolated func isAcceptable(rawCode: String, code: String, context: String) -> Bool {
        if rawCode.filter({ $0 == "-" }).count > 1 {
            return false
        }

        if code.allSatisfy({ $0 == "0" }) || code.allSatisfy({ $0.isLetter }) {
            return false
        }

        let loweredContext = context.lowercased()
        if loweredContext.contains("#\(code.lowercased())") {
            return false
        }

        if code.count == 4,
           let year = Int(code),
           (1900...2099).contains(year) {
            return false
        }

        if containsAny(loweredContext, ["金额", "¥", "$", "rmb", "usd", "price", "amount", "订单", "流水", "发票", "invoice", "order", "ticket", "serial"]) {
            return false
        }

        return true
    }

    private nonisolated func confidence(for candidate: CandidateCode) -> Double {
        let base = candidate.keyword.id.contains("code") || candidate.keyword.id.contains("码") || candidate.keyword.id.contains("otp") ? 0.95 : 0.88
        let distancePenalty = min(Double(candidate.distance) / 250.0, 0.24)
        return max(0.62, base - distancePenalty)
    }

    private nonisolated func keywordMatches(in text: String) -> [KeywordMatch] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        return Self.keywordDefinitions.flatMap { keyword in
            keyword.expression.matches(in: text, range: fullRange).map { match in
                KeywordMatch(id: keyword.id, range: match.range)
            }
        }
    }

    private nonisolated func nearestKeyword(to range: NSRange, keywords: [KeywordMatch]) -> KeywordMatch? {
        keywords.min { lhs, rhs in
            distanceBetween(range, lhs.range) < distanceBetween(range, rhs.range)
        }
    }

    private nonisolated func distanceBetween(_ lhs: NSRange, _ rhs: NSRange) -> Int {
        let lhsEnd = lhs.location + lhs.length
        let rhsEnd = rhs.location + rhs.length

        if lhs.location >= rhsEnd {
            return lhs.location - rhsEnd
        }

        if rhs.location >= lhsEnd {
            return rhs.location - lhsEnd
        }

        return 0
    }

    private nonisolated func expandedContextRange(around range: NSRange, in textLength: Int) -> NSRange {
        let start = max(0, range.location - 32)
        let end = min(textLength, range.location + range.length + 32)
        return NSRange(location: start, length: end - start)
    }

    private nonisolated func validationContextRange(around range: NSRange, in textLength: Int) -> NSRange {
        let start = max(0, range.location - 14)
        let end = min(textLength, range.location + range.length + 14)
        return NSRange(location: start, length: end - start)
    }

    private nonisolated static func htmlToText(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return html
        }

        return attributed.string
    }

    private nonisolated static func containsHTML(in text: String) -> Bool {
        text.range(of: #"<[A-Za-z][^>]*>"#, options: .regularExpression) != nil
    }

    private nonisolated static func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizeCharacter(_ character: Character) -> Character {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return character
        }

        let value = scalar.value
        if (0xFF10...0xFF19).contains(value),
           let normalized = UnicodeScalar(value - 0xFF10 + 0x30) {
            return Character(normalized)
        }

        return character
    }

    private nonisolated func sanitizedContext(_ context: String) -> String {
        let collapsed = context
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 72 else {
            return collapsed
        }

        return String(collapsed.prefix(72)) + "..."
    }

    private nonisolated static func expirationDate(from text: String, receivedAt: Date) -> Date? {
        let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*(分钟|minutes?|mins?)"#, options: .caseInsensitive)
        let range = NSRange(location: 0, length: (text as NSString).length)

        guard
            let match = regex?.firstMatch(in: text, range: range),
            let minuteRange = Range(match.range(at: 1), in: text),
            let minutes = Int(text[minuteRange])
        else {
            return nil
        }

        return Calendar.current.date(byAdding: .minute, value: minutes, to: receivedAt)
    }

    private nonisolated func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }

    private nonisolated static let candidateExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9０-９])(?=[A-Za-z0-9０-９-]*[0-9０-９])[A-Za-z0-9０-９][A-Za-z0-9０-９-]{3,11}(?![A-Za-z0-9０-９])"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )

    private nonisolated static let keywordDefinitions: [(id: String, expression: NSRegularExpression)] = [
        "verification code",
        "security code",
        "login code",
        "confirmation code",
        "authentication code",
        "captcha code",
        "auth code",
        "one-time password",
        "dynamic password",
        "验证码",
        "校验码",
        "动态验证码",
        "动态密码",
        "一次性密码",
        "登录码",
        "确认码",
        "安全码",
        "代码",
        "verification",
        "captcha",
        "passcode",
        "otp",
        "pin",
        "code",
        "인증"
    ].map { keyword in
        (keyword, try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: keyword), options: [.caseInsensitive]))
    }
}

private extension Character {
    nonisolated var isASCIIAlphanumeric: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }

        let value = Int(scalar.value)
        return (48...57).contains(value)
            || (65...90).contains(value)
            || (97...122).contains(value)
    }
}
