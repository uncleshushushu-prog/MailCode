//
//  VerificationCodePattern.swift
//  MailCode
//
//  Created by Codex on 2026/6/2.
//

import Foundation

struct VerificationCodePattern {
    enum Kind {
        case contextual
        case numeric
        case separatedNumeric
        case alphaNumeric
        case looseUpperAlphaNumeric
    }

    let id: String
    let priority: Int
    let kind: Kind
    let expression: NSRegularExpression
    let codeCaptureGroup: Int
    let normalizedLength: ClosedRange<Int>

    init(
        id: String,
        priority: Int,
        kind: Kind,
        pattern: String,
        options: NSRegularExpression.Options = [],
        codeCaptureGroup: Int = 1,
        normalizedLength: ClosedRange<Int>
    ) {
        self.id = id
        self.priority = priority
        self.kind = kind
        self.expression = try! NSRegularExpression(pattern: pattern, options: options)
        self.codeCaptureGroup = codeCaptureGroup
        self.normalizedLength = normalizedLength
    }

    nonisolated func normalizedCode(from rawCode: String) -> String? {
        let normalized = rawCode
            .map(Self.normalizeCharacter)
            .filter { character in
                switch kind {
                case .separatedNumeric, .contextual:
                    return character != " " && character != "-" && character != "\n" && character != "\r" && character != "\t"
                case .numeric, .alphaNumeric, .looseUpperAlphaNumeric:
                    return true
                }
            }
            .map(String.init)
            .joined()

        guard normalizedLength.contains(normalized.count) else {
            return nil
        }

        switch kind {
        case .numeric, .separatedNumeric:
            return normalized.allSatisfy { $0.isASCIIAlphanumericDigit } ? normalized : nil
        case .contextual, .alphaNumeric, .looseUpperAlphaNumeric:
            return normalized.allSatisfy { $0.isASCIIAlphanumeric } ? normalized : nil
        }
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
}

private extension Character {
    nonisolated var isASCIIAlphanumericDigit: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }

        return (48...57).contains(Int(scalar.value))
    }

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
