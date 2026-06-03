//
//  VerificationCodeCandidate.swift
//  MailCode
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum VerificationCodeCandidateSource {
    case subject
    case plainTextBody
    case htmlTextBody

    nonisolated var displayName: String {
        switch self {
        case .subject:
            "主题"
        case .plainTextBody:
            "纯文本正文"
        case .htmlTextBody:
            "HTML 正文"
        }
    }
}

struct VerificationCodeCandidate {
    var code: String
    var rawCode: String
    var source: VerificationCodeCandidateSource
    var location: Int
    var textLength: Int
    var context: String
    var pattern: VerificationCodePattern
}
